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

struct CSVParseResult {
    var medications: [Medication]
    var errors: [CSVParseError]
}

/// Parses medication schedules from CSV text in the format:
///
///     name,dosage,unit,times
///     Metformin,500,mg,08:00;20:00
///
/// - The header row is optional (detected case-insensitively).
/// - `times` holds one or more 24-hour `HH:mm` values separated by `;`.
/// - Fields may be quoted (`"Vitamin D3, chewable"`), with `""` as an escaped quote.
/// - Invalid rows are reported with their line number; valid rows are still imported.
enum CSVMedicationParser {
    static func parse(_ text: String) -> CSVParseResult {
        var medications: [Medication] = []
        var errors: [CSVParseError] = []

        // Normalize line endings so Windows/Excel exports parse the same way.
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let fields = splitFields(line).map { $0.trimmingCharacters(in: .whitespaces) }

            // Skip the header row wherever it appears first.
            if medications.isEmpty, errors.isEmpty, fields.first?.lowercased() == "name" {
                continue
            }

            guard fields.count == 4 else {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Expected 4 columns (name, dosage, unit, times) but found \(fields.count)."
                ))
                continue
            }

            let name = fields[0]
            guard !name.isEmpty else {
                errors.append(CSVParseError(line: lineNumber, message: "Medication name is empty."))
                continue
            }

            guard let dosage = Double(fields[1]), dosage > 0 else {
                errors.append(CSVParseError(line: lineNumber, message: "Dosage “\(fields[1])” is not a positive number."))
                continue
            }

            let unit = fields[2]
            guard !unit.isEmpty else {
                errors.append(CSVParseError(line: lineNumber, message: "Unit is empty."))
                continue
            }

            let timeStrings = fields[3]
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !timeStrings.isEmpty else {
                errors.append(CSVParseError(line: lineNumber, message: "No times given."))
                continue
            }

            let parsedTimes = timeStrings.map { ($0, TimeOfDay(string: $0)) }
            let invalid = parsedTimes.filter { $0.1 == nil }.map(\.0)
            guard invalid.isEmpty else {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Invalid time \(invalid.map { "“\($0)”" }.joined(separator: ", ")). Use 24-hour HH:mm."
                ))
                continue
            }

            // Remove duplicate times within one row.
            let times = Array(Set(parsedTimes.compactMap(\.1))).sorted()
            medications.append(Medication(name: name, dosage: dosage, unit: unit, times: times))
        }

        return CSVParseResult(medications: medications, errors: errors)
    }

    /// Splits one CSV line on commas, honoring double-quoted fields.
    private static func splitFields(_ line: String) -> [String] {
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
