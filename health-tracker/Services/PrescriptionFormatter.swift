//
//  PrescriptionFormatter.swift
//  health-tracker
//
//  Turns a `Medication`'s structured fields into prescription-style text, e.g.
//  "Take 1 capsule (500 mg) by mouth 3 times daily (8:00 AM, 2:00 PM, 8:00 PM) with food
//  for 10 days for infection." Every screen and notification uses this so wording is consistent.
//

import Foundation

struct PrescriptionFormatter {
    var locale: Locale = .current
    var calendar: Calendar = .current

    // MARK: - Full text

    /// Label-style name, e.g. "Glucophage (metformin) 500 mg tablet" or "Albuterol HFA 90 mcg".
    func title(for medication: Medication) -> String {
        var parts = [medication.name]
        if let generic = medication.genericName {
            parts.append("(\(generic))")
        }
        if let strength = medication.strength {
            parts.append(strengthText(strength))
        }
        // Only solid forms read naturally after the strength on a label.
        if [.tablet, .capsule, .patch, .suppository].contains(medication.form) {
            parts.append(medication.form.singular)
        }
        return parts.joined(separator: " ")
    }

    /// The instruction sentence ("sig").
    func instruction(for medication: Medication) -> String {
        var parts = [medication.route.verb]

        var dose = quantityText(medication.quantity, form: medication.form)
        if let amount = medication.doseAmount {
            dose += " (\(amountText(amount)))"
        }
        parts.append(dose)

        if let phrase = medication.route.phrase {
            parts.append(phrase)
        }

        let purpose = medication.purpose.flatMap(normalizedPurpose)
        parts.append(scheduleText(medication.schedule, purpose: purpose))

        let inlineFood = medication.foodRules.filter(\.isInline).sorted().map(\.phrase)
        if !inlineFood.isEmpty {
            parts.append(inlineFood.formatted(.list(type: .and).locale(locale)))
        }

        if let course = medication.course {
            parts.append("for \(count(course.days, "day", "days"))")
        }

        // As-needed schedules already include the purpose ("as needed for wheezing").
        if let purpose, !medication.schedule.isAsNeeded {
            parts.append("for \(purpose)")
        }

        return parts.joined(separator: " ") + "."
    }

    /// Separate safety lines shown under the instruction.
    func warnings(for medication: Medication) -> [String] {
        var lines: [String] = []

        if case .asNeeded(_, let maxDoses) = medication.schedule {
            let maxUnits = quantityText(medication.quantity * Double(maxDoses), form: medication.form)
            if medication.quantity == 1 {
                lines.append("No more than \(maxUnits) in 24 hours.")
            } else {
                lines.append("No more than \(maxUnits) (\(count(maxDoses, "dose", "doses"))) in 24 hours.")
            }
        }

        if medication.course != nil {
            lines.append("Take every dose until the course is finished, even if you feel better.")
        }

        lines += medication.foodRules.filter { !$0.isInline }.sorted().map(\.phrase)
        return lines
    }

    /// Compact line for list rows, e.g. "1 capsule · with food · day 3 of 10".
    func subtitle(for medication: Medication, on day: Date) -> String {
        var parts = [quantityText(medication.quantity, form: medication.form)]
        if medication.schedule.isAsNeeded {
            parts.append("as needed")
        }
        parts += medication.foodRules.filter(\.isInline).sorted().map(\.phrase)
        if let course = medication.course, let dayNumber = course.dayNumber(on: day, calendar: calendar) {
            parts.append("day \(dayNumber) of \(course.days)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Pieces

    /// "1 tablet", "½ tablet", "1½ tablets", "2 puffs", "7.5 mL".
    func quantityText(_ quantity: Double, form: DoseForm) -> String {
        let number = form == .milliliter ? decimal(quantity) : fractional(quantity)
        return "\(number) \(quantity <= 1 ? form.singular : form.plural)"
    }

    /// "500 mg", "0.1%", "5 mg/5 mL", "100 units/mL".
    func strengthText(_ strength: Strength) -> String {
        let value = strength.unit == "%" ? "\(decimal(strength.value))%" : "\(decimal(strength.value)) \(strength.unit)"
        guard let perUnit = strength.perVolumeUnit else { return value }
        let perVolume = strength.perVolume ?? 1
        return perVolume == 1 ? "\(value)/\(perUnit)" : "\(value)/\(decimal(perVolume)) \(perUnit)"
    }

    /// "1,000 mg", "0.075 mg".
    func amountText(_ amount: DoseAmount) -> String {
        "\(decimal(amount.value)) \(amount.unit)"
    }

    /// "twice daily (8:00 AM, 8:00 PM)", "every 8 hours (…)", "on Monday and Thursday (8:00 AM)",
    /// "at bedtime (10:00 PM)", "as needed for wheezing, at least 4 hours apart".
    func scheduleText(_ schedule: DoseSchedule, purpose: String? = nil) -> String {
        switch schedule {
        case .daily(let times):
            return "\(timesPerDay(times.count)) (\(timeList(schedule.times)))"
        case .everyHours(let interval, _):
            return "every \(count(interval, "hour", "hours")) (\(timeList(schedule.times)))"
        case .atBedtime(let time):
            return "at bedtime (\(timeText(time)))"
        case .weekly(let days, let times):
            let dayList = days.sorted().map(\.name).formatted(.list(type: .and).locale(locale))
            let prefix = times.count > 1 ? "\(timesPerDay(times.count)) " : ""
            return "\(prefix)on \(dayList) (\(timeList(schedule.times)))"
        case .asNeeded(let minHours, _):
            var text = "as needed"
            if let purpose { text += " for \(purpose)" }
            return text + ", at least \(hoursText(minHours)) apart"
        }
    }

    func timeText(_ time: TimeOfDay) -> String {
        time.date(calendar: calendar)
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    // MARK: - Helpers

    private func timeList(_ times: [TimeOfDay]) -> String {
        times.map(timeText).joined(separator: ", ")
    }

    private func timesPerDay(_ n: Int) -> String {
        switch n {
        case 1: "once daily"
        case 2: "twice daily"
        default: "\(n) times daily"
        }
    }

    private func hoursText(_ hours: Double) -> String {
        if hours < 1 {
            return count(Int((hours * 60).rounded()), "minute", "minutes")
        }
        return "\(decimal(hours)) \(hours == 1 ? "hour" : "hours")"
    }

    private func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// Up to 4 decimals so small strengths (0.075 mg) are never rounded.
    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).locale(locale))
    }

    /// Common tablet fractions as glyphs ("½", "1½"); anything else as a decimal.
    private func fractional(_ value: Double) -> String {
        let whole = value.rounded(.down)
        let glyph: String? = switch value - whole {
        case 0: ""
        case 0.25: "¼"
        case 0.5: "½"
        case 0.75: "¾"
        default: nil
        }
        guard let glyph else { return decimal(value) }
        if glyph.isEmpty { return decimal(whole) }
        return whole == 0 ? glyph : "\(decimal(whole))\(glyph)"
    }

    /// "For blood pressure." → "blood pressure".
    private func normalizedPurpose(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("for ") { text = String(text.dropFirst(4)) }
        while text.hasSuffix(".") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
