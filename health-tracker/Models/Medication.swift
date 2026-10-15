//
//  Medication.swift
//  health-tracker
//

import Foundation

/// A time of day (24-hour clock) at which something is scheduled.
struct TimeOfDay: Hashable, Comparable, Identifiable {
    let hour: Int
    let minute: Int

    var id: Int { hour * 60 + minute }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Parses a strict 24-hour `HH:mm` (or `H:mm`) string. Returns `nil` when invalid.
    init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// `HH:mm` representation, e.g. "08:00".
    var formatted24h: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Today's date at this time, used for display with locale-aware formatting.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.id < rhs.id
    }
}

extension Date {
    /// Default "taken at" when logging for `day`: now if `day` is today; otherwise the
    /// scheduled time on that day, or the current clock time on that day if unscheduled.
    static func defaultLogTime(on day: Date, scheduled: TimeOfDay?, calendar: Calendar = .current) -> Date {
        let now = Date.now
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let time = scheduled ?? TimeOfDay(hour: parts.hour ?? 12, minute: parts.minute ?? 0)
        return min(time.date(on: day, calendar: calendar), now)
    }
}

struct Medication: Identifiable, Hashable {
    let id: UUID
    var name: String
    var dosage: Double
    var unit: String
    var times: [TimeOfDay]
    /// When this medication was first added. Earlier days don't show its doses as missed.
    var addedOn: Date

    init(id: UUID = UUID(), name: String, dosage: Double, unit: String, times: [TimeOfDay], addedOn: Date = .now) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.unit = unit
        self.times = times.sorted()
        self.addedOn = addedOn
    }

    /// e.g. "10 mg", "2.5 ml" or "0.075 mg". Allows up to 4 decimals so small doses are never rounded.
    var displayDosage: String {
        "\(dosage.formatted(.number.precision(.fractionLength(0...4)))) \(unit)"
    }
}
