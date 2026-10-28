//
//  AlarmPlanner.swift
//  health-tracker
//
//  Decides which alarms to create (in addition to notifications). Pure (no AlarmKit calls) so
//  the plan can be tested; `AlarmScheduler` turns it into AlarmKit alarms.
//
//  - Everything due at the same time shares one alarm, whose label lists what's due.
//  - Alarms repeat weekly on the days they're needed; all seven days means daily.
//  - If what's due at a time differs by day (e.g. one medication daily at 8 AM and another on
//    Mondays at 8 AM), that time gets one alarm per distinct combination, on non-overlapping
//    days — so only one alarm ever rings at a time, and its label is accurate for that day.
//  - Days come from the coming week (today included), so courses ending and medications
//    starting within the week only ring on their days. Alarms can't stop on a date, so they're
//    created again whenever the user asks.
//  - As-needed medications and disabled measurement reminders get no alarms.
//

import Foundation

struct PlannedAlarm: Hashable, Identifiable {
    let time: TimeOfDay
    /// Days the alarm rings; all seven for a daily alarm.
    let weekdays: Set<Weekday>
    /// Names of medications due, in the order of the medication list.
    let medications: [String]
    /// Measurements due, in the order of the reminders list.
    let measurements: [MeasurementKind]

    var id: String {
        "\(time.id).\(weekdays.map(\.rawValue).sorted().map(String.init).joined(separator: ","))"
    }

    var isDaily: Bool { weekdays.count == Weekday.allCases.count }

    /// The alarm's label, e.g. "Take Metformin, Lisinopril · Measure blood pressure".
    var title: String {
        var parts: [String] = []
        if !medications.isEmpty {
            parts.append("Take \(medications.joined(separator: ", "))")
        }
        if !measurements.isEmpty {
            parts.append("Measure \(measurements.map { $0.label.lowercased() }.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    /// "Every day", "Weekdays", "Weekends", or the days, e.g. "Mon, Wed, Fri".
    var daysText: String {
        let weekend: Set<Weekday> = [.saturday, .sunday]
        if isDaily { return "Every day" }
        if weekdays == Set(Weekday.allCases).subtracting(weekend) { return "Weekdays" }
        if weekdays == weekend { return "Weekends" }
        return weekdays.sorted().map { String($0.name.prefix(3)) }.joined(separator: ", ")
    }
}

enum AlarmPlanner {
    static func plan(
        medications: [Medication],
        measurementReminders: [MeasurementReminder],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedAlarm] {
        /// What's due in one slot (a time on a weekday).
        struct Due: Hashable {
            var medications: [String] = []
            var measurements: [MeasurementKind] = []
        }
        var slots: [TimeOfDay: [Weekday: Due]] = [:]

        let today = calendar.startOfDay(for: now)
        for offset in 0..<Weekday.allCases.count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            else { continue }

            for medication in medications where medication.isScheduled(on: day, calendar: calendar) {
                for time in medication.times where !(slots[time]?[weekday]?.medications.contains(medication.name) ?? false) {
                    slots[time, default: [:]][weekday, default: Due()].medications.append(medication.name)
                }
            }
            for reminder in measurementReminders where reminder.isEnabled {
                for time in Set(reminder.times) {
                    slots[time, default: [:]][weekday, default: Due()].measurements.append(reminder.kind)
                }
            }
        }

        var alarms: [PlannedAlarm] = []
        for time in slots.keys.sorted() {
            // Days with exactly the same things due share an alarm.
            let byContents = Dictionary(grouping: slots[time] ?? [:], by: \.value)
            let timeAlarms = byContents.map { due, days in
                PlannedAlarm(time: time, weekdays: Set(days.map(\.key)),
                             medications: due.medications, measurements: due.measurements)
            }
            // Stable order within a time: the alarm covering the most days first.
            alarms += timeAlarms.sorted {
                ($0.weekdays.count, $0.title) > ($1.weekdays.count, $1.title)
            }
        }
        return alarms
    }
}
