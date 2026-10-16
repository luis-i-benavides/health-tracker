//
//  CSVMedicationParser.swift
//  health-tracker
//

import Foundation

struct CSVParseError: Identifiable, Hashable, Error {
    let line: Int
    let message: String

    var id: String { "\(line):\(message)" }
}

enum CSVFormat: Hashable {
    /// Original `name,dosage,unit,times` (header optional).
    case legacy
    /// Prescription columns identified by header name.
    case prescription
}

struct CSVParseResult {
    var medications: [Medication]
    var errors: [CSVParseError]
    var format: CSVFormat = .legacy
}

/// Parses a medication list from CSV. Two formats are accepted:
///
/// **Prescription format** — columns identified by header, in any order. Only `name`,
/// `strength` and `frequency` are required:
///
///     name,strength,form,quantity,route,frequency,food,duration_days,purpose
///     Amoxicillin,500 mg,capsule,1,by mouth,TID,with food,10,infection
///     Albuterol HFA,90 mcg,puff,2,inhaled,as needed,,,wheezing   (plus max_per_24h)
///
/// Columns: name, generic, strength, form, quantity, route, frequency, times, food,
/// max_per_24h, min_hours_apart, duration_days, start, purpose.
///
/// **Legacy format** — `name,dosage,unit,times` with an optional header; imported as a
/// daily medication taken by mouth at the listed times.
///
/// In both formats fields may be quoted (`"Vitamin D3, chewable"`, `""` escapes a quote),
/// lists use `;`, times are 24-hour `HH:mm`, and invalid rows are reported with their line
/// number while valid rows are still imported.
enum CSVMedicationParser {
    static let prescriptionColumns = [
        "name", "generic", "strength", "form", "quantity", "route", "frequency", "times", "food",
        "max_per_24h", "min_hours_apart", "duration_days", "start", "purpose",
    ]
    static let requiredColumns = ["name", "strength", "frequency"]

    /// - Parameters:
    ///   - today: Used as the start date for courses and medications without a `start` value.
    static func parse(_ text: String, today: Date = .now, calendar: Calendar = .current) -> CSVParseResult {
        // Normalize line endings so Windows/Excel exports parse the same way.
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .enumerated()
            .map { (number: $0.offset + 1, text: $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }

        guard let first = lines.first else {
            return CSVParseResult(medications: [], errors: [])
        }

        let firstFields = splitFields(first.text).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // Prescription columns may come in any order, so look for "name" anywhere in the first line.
        let hasHeader = firstFields.contains("name")
        let isLegacyHeader = firstFields == ["name", "dosage", "unit", "times"]

        if hasHeader && !isLegacyHeader {
            return parsePrescription(header: firstFields, headerLine: first.number,
                                     rows: Array(lines.dropFirst()), today: today, calendar: calendar)
        }
        return parseLegacy(rows: hasHeader ? Array(lines.dropFirst()) : lines, today: today)
    }

    // MARK: - Prescription format

    private struct RowError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func parsePrescription(
        header: [String], headerLine: Int, rows: [(number: Int, text: String)],
        today: Date, calendar: Calendar
    ) -> CSVParseResult {
        var result = CSVParseResult(medications: [], errors: [], format: .prescription)

        let unknown = header.filter { !prescriptionColumns.contains($0) }
        if !unknown.isEmpty {
            result.errors.append(CSVParseError(
                line: headerLine,
                message: "Unknown column \(unknown.map { "“\($0)”" }.joined(separator: ", ")); it was ignored. "
                    + "Known columns: \(prescriptionColumns.joined(separator: ", "))."
            ))
        }
        let missing = requiredColumns.filter { !header.contains($0) }
        if !missing.isEmpty {
            result.errors.append(CSVParseError(
                line: headerLine,
                message: "Missing required column \(missing.map { "“\($0)”" }.joined(separator: ", "))."
            ))
            return result
        }

        for row in rows {
            let fields = splitFields(row.text).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count <= header.count else {
                result.errors.append(CSVParseError(
                    line: row.number,
                    message: "Row has \(fields.count) columns but the header has \(header.count)."
                ))
                continue
            }
            // Trailing empty columns may be left off.
            let value: (String) -> String = { column in
                guard let index = header.firstIndex(of: column), index < fields.count else { return "" }
                return fields[index]
            }
            do {
                result.medications.append(try medication(from: value, today: today, calendar: calendar))
            } catch let error as RowError {
                result.errors.append(CSVParseError(line: row.number, message: error.message))
            } catch {
                result.errors.append(CSVParseError(line: row.number, message: error.localizedDescription))
            }
        }
        return result
    }

    private static func medication(
        from value: (String) -> String, today: Date, calendar: Calendar
    ) throws -> Medication {
        let name = value("name")
        guard !name.isEmpty else { throw RowError("Medication name is empty.") }

        let generic = value("generic")
        let strength = try parseStrength(value("strength"))

        let formText = value("form")
        let form: DoseForm
        if formText.isEmpty {
            form = .tablet
        } else if let parsed = DoseForm.parse(formText) {
            form = parsed
        } else {
            throw RowError("Unknown form “\(formText)”. Use one of: \(DoseForm.allCases.map(\.singular).joined(separator: ", ")).")
        }

        let quantityText = value("quantity")
        let quantity: Double
        if quantityText.isEmpty {
            quantity = 1
        } else if let parsed = parseQuantity(quantityText), parsed > 0 {
            quantity = parsed
        } else {
            throw RowError("Quantity “\(quantityText)” must be a positive number, e.g. 1, 2, 0.5 or 1/2.")
        }

        let routeText = value("route")
        let route: Route
        if routeText.isEmpty {
            route = .byMouth
        } else if let parsed = Route.parse(routeText) {
            route = parsed
        } else {
            throw RowError("Unknown route “\(routeText)”. Use e.g. by mouth, under the tongue, inhaled, topical, transdermal, eye, ear, nasal, injection, intramuscular or rectal.")
        }

        let schedule = try parseSchedule(
            frequency: value("frequency"), times: value("times"),
            maxPer24h: value("max_per_24h"), minHoursApart: value("min_hours_apart")
        )
        let foodRules = try parseFoodRules(value("food"))

        let startText = value("start")
        let start: Date
        if startText.isEmpty {
            start = today
        } else if let parsed = parseDate(startText, calendar: calendar) {
            start = parsed
        } else {
            throw RowError("Start date “\(startText)” must be YYYY-MM-DD.")
        }

        let durationText = value("duration_days")
        var course: Course?
        if !durationText.isEmpty {
            guard let days = Int(durationText), days > 0 else {
                throw RowError("duration_days “\(durationText)” must be a whole number of days, e.g. 10.")
            }
            course = Course(startDate: start, days: days, calendar: calendar)
        }

        let purpose = value("purpose")
        return Medication(
            name: name,
            genericName: generic.isEmpty || generic.caseInsensitiveCompare(name) == .orderedSame ? nil : generic,
            strength: strength,
            form: form,
            quantity: quantity,
            route: route,
            schedule: schedule,
            foodRules: foodRules,
            course: course,
            purpose: purpose.isEmpty ? nil : purpose,
            addedOn: calendar.startOfDay(for: start)
        )
    }

    private static func parseStrength(_ text: String) throws -> Strength {
        guard !text.isEmpty else { throw RowError("Strength is required, e.g. 500 mg.") }
        if let strength = Strength(parsing: text) { return strength }
        if Double(text) != nil {
            throw RowError("Strength “\(text)” needs a unit, e.g. \(text) mg.")
        }
        throw RowError("Strength “\(text)” isn't recognized. Use a number and unit, e.g. 500 mg, 90 mcg, 5 gr, 5 mg/5 mL or 0.1%.")
    }

    /// "1", "0.5", ".5", "1/2", "½", "1½", "1 1/2".
    static func parseQuantity(_ text: String) -> Double? {
        let glyphs: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75]
        var text = text.trimmingCharacters(in: .whitespaces)
        var total = 0.0
        if let last = text.last, let fraction = glyphs[last] {
            total += fraction
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { return total }
        }
        let parts = text.split(separator: " ")
        for part in parts {
            if let number = Double(part) {
                total += number
            } else {
                let pieces = part.split(separator: "/")
                guard pieces.count == 2, let n = Double(pieces[0]), let d = Double(pieces[1]), d != 0 else { return nil }
                total += n / d
            }
        }
        return parts.isEmpty ? nil : total
    }

    private static func parseSchedule(
        frequency rawFrequency: String, times rawTimes: String,
        maxPer24h: String, minHoursApart: String
    ) throws -> DoseSchedule {
        let frequency = rawFrequency
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !frequency.isEmpty else {
            throw RowError("Frequency is required, e.g. once daily, twice daily, every 8 hours, Mon;Thu or as needed.")
        }

        // Explicit times, if any.
        let timeStrings = rawTimes.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let parsedTimes = timeStrings.map { ($0, TimeOfDay(string: $0)) }
        let invalidTimes = parsedTimes.filter { $0.1 == nil }.map(\.0)
        guard invalidTimes.isEmpty else {
            throw RowError("Invalid time \(invalidTimes.map { "“\($0)”" }.joined(separator: ", ")). Use 24-hour HH:mm.")
        }
        let times = Array(Set(parsedTimes.compactMap(\.1))).sorted()

        let isAsNeeded = ["as needed", "prn", "as needed (prn)"].contains(frequency)
        if !isAsNeeded {
            if !maxPer24h.isEmpty { throw RowError("max_per_24h only applies to as-needed medications.") }
            if !minHoursApart.isEmpty { throw RowError("min_hours_apart only applies to as-needed medications.") }
        }

        /// One time from the times column, or the default.
        func singleTime(_ defaultTime: TimeOfDay, for label: String) throws -> TimeOfDay {
            guard times.count <= 1 else { throw RowError("“\(label)” takes one time, but \(times.count) were given.") }
            return times.first ?? defaultTime
        }

        if isAsNeeded {
            guard times.isEmpty else {
                throw RowError("As-needed medications don't have scheduled times; leave times empty.")
            }
            guard !maxPer24h.isEmpty else {
                throw RowError("As-needed medications need max_per_24h (the most doses allowed in 24 hours).")
            }
            guard let maxDoses = Int(maxPer24h), maxDoses > 0 else {
                throw RowError("max_per_24h “\(maxPer24h)” must be a whole number, e.g. 4.")
            }
            var minHours = 4.0
            if !minHoursApart.isEmpty {
                guard let parsed = Double(minHoursApart), parsed > 0 else {
                    throw RowError("min_hours_apart “\(minHoursApart)” must be a positive number of hours, e.g. 4.")
                }
                minHours = parsed
            }
            return .asNeeded(minHoursApart: minHours, maxDosesPer24h: maxDoses)
        }

        // Fixed number of doses per day.
        if let perDay = dosesPerDay(frequency) {
            if times.isEmpty {
                guard let defaults = defaultTimes(perDay: perDay) else {
                    throw RowError("Give \(perDay) times for “\(rawFrequency)”, e.g. 06:00;10:00;14:00….")
                }
                return .daily(times: defaults)
            }
            guard times.count == perDay else {
                throw RowError("“\(rawFrequency)” needs \(perDay) time\(perDay == 1 ? "" : "s"), but \(times.count) \(times.count == 1 ? "was" : "were") given.")
            }
            return .daily(times: times)
        }

        switch frequency {
        case "every morning", "qam", "in the morning":
            return .daily(times: [try singleTime(TimeOfDay(hour: 8, minute: 0), for: rawFrequency)])
        case "every evening", "qpm", "in the evening":
            return .daily(times: [try singleTime(TimeOfDay(hour: 20, minute: 0), for: rawFrequency)])
        case "at bedtime", "bedtime", "qhs", "hs", "nightly at bedtime":
            return .atBedtime(try singleTime(TimeOfDay(hour: 22, minute: 0), for: rawFrequency))
        default:
            break
        }

        // Every N hours: "every 8 hours", "q8h", "q 8 hrs".
        if let match = frequency.wholeMatch(of: /(?:every|q) ?(\d+) ?(?:h|hr|hrs|hour|hours)/),
           let interval = Int(match.1) {
            guard (1...24).contains(interval), 24 % interval == 0 else {
                throw RowError("“\(rawFrequency)” must divide evenly into 24 hours (every 1, 2, 3, 4, 6, 8, 12 or 24 hours).")
            }
            let defaultFirst = TimeOfDay(hour: interval >= 12 ? 8 : 6, minute: 0)
            return .everyHours(interval: interval, firstDose: try singleTime(defaultFirst, for: rawFrequency))
        }

        // Weekdays: "Mon;Wed;Fri", "weekly on Mon/Thu", "every Tuesday".
        var dayText = frequency
        for prefix in ["weekly on ", "every ", "on ", "weekly "] where dayText.hasPrefix(prefix) {
            dayText = String(dayText.dropFirst(prefix.count))
        }
        let tokens = dayText.split { ";,/ ".contains($0) }.map(String.init).filter { $0 != "and" }
        if !tokens.isEmpty {
            let days = tokens.compactMap { Weekday.parse($0) }
            if days.count == tokens.count {
                return .weekly(days: Set(days), times: times.isEmpty ? [TimeOfDay(hour: 8, minute: 0)] : times)
            }
        }
        if frequency == "weekly" {
            throw RowError("“weekly” needs the days, e.g. Mon or Mon;Thu.")
        }

        throw RowError("Unknown frequency “\(rawFrequency)”. Use e.g. once daily, twice daily, 3 times daily, every 8 hours, at bedtime, Mon;Wed;Fri or as needed.")
    }

    /// "once daily" → 1, "BID" → 2, "3 times a day" → 3, "4x daily" → 4.
    private static func dosesPerDay(_ frequency: String) -> Int? {
        switch frequency {
        case "once daily", "once a day", "daily", "qd", "every day", "once": return 1
        case "twice daily", "twice a day", "bid": return 2
        case "three times daily", "three times a day", "tid": return 3
        case "four times daily", "four times a day", "qid": return 4
        default: break
        }
        if let match = frequency.wholeMatch(of: /(\d+) ?(?:x|times) ?(?:daily|a day|per day)/),
           let n = Int(match.1), n > 0 {
            return n
        }
        return nil
    }

    /// Waking-hours defaults ("twice daily" = 8 AM and 8 PM). Beyond 4 a day, times must be given.
    private static func defaultTimes(perDay: Int) -> [TimeOfDay]? {
        let hours: [Int]? = switch perDay {
        case 1: [8]
        case 2: [8, 20]
        case 3: [8, 14, 20]
        case 4: [8, 12, 16, 20]
        default: nil
        }
        return hours?.map { TimeOfDay(hour: $0, minute: 0) }
    }

    private static func parseFoodRules(_ text: String) throws -> Set<FoodRule> {
        var rules = Set<FoodRule>()
        for token in text.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            guard let rule = FoodRule.parse(token) else {
                throw RowError("Unknown food rule “\(token)”. Use: with food, empty stomach, full glass of water, avoid grapefruit, avoid alcohol.")
            }
            rules.insert(rule)
        }
        if rules.contains(.withFood) && rules.contains(.emptyStomach) {
            throw RowError("Food rules “with food” and “empty stomach” contradict each other.")
        }
        return rules
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2]   // rejects 2026-02-31
        else { return nil }
        return date
    }

    // MARK: - Legacy format

    private static func parseLegacy(rows: [(number: Int, text: String)], today: Date) -> CSVParseResult {
        var medications: [Medication] = []
        var errors: [CSVParseError] = []

        for row in rows {
            let fields = splitFields(row.text).map { $0.trimmingCharacters(in: .whitespaces) }

            guard fields.count == 4 else {
                errors.append(CSVParseError(
                    line: row.number,
                    message: "Expected 4 columns (name, dosage, unit, times) but found \(fields.count)."
                ))
                continue
            }

            let name = fields[0]
            guard !name.isEmpty else {
                errors.append(CSVParseError(line: row.number, message: "Medication name is empty."))
                continue
            }

            guard let dosage = Double(fields[1]), dosage > 0 else {
                errors.append(CSVParseError(line: row.number, message: "Dosage “\(fields[1])” is not a positive number."))
                continue
            }

            let unit = fields[2]
            guard !unit.isEmpty else {
                errors.append(CSVParseError(line: row.number, message: "Unit is empty."))
                continue
            }

            let timeStrings = fields[3]
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !timeStrings.isEmpty else {
                errors.append(CSVParseError(line: row.number, message: "No times given."))
                continue
            }

            let parsedTimes = timeStrings.map { ($0, TimeOfDay(string: $0)) }
            let invalid = parsedTimes.filter { $0.1 == nil }.map(\.0)
            guard invalid.isEmpty else {
                errors.append(CSVParseError(
                    line: row.number,
                    message: "Invalid time \(invalid.map { "“\($0)”" }.joined(separator: ", ")). Use 24-hour HH:mm."
                ))
                continue
            }

            // Remove duplicate times within one row.
            let times = Array(Set(parsedTimes.compactMap(\.1))).sorted()
            medications.append(Medication(name: name, dosage: dosage, unit: unit, times: times, addedOn: today))
        }

        return CSVParseResult(medications: medications, errors: errors, format: .legacy)
    }

    // MARK: - Fields

    /// Splits one CSV line on commas, honoring double-quoted fields.
    static func splitFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = iterator.next()

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        // Escaped quote inside a quoted field.
                        current.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
