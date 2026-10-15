//
//  ReminderPlanner.swift
//  health-tracker
//
//  Decides which local notifications to schedule. Pure (no UserNotifications calls) so the
//  plan can be tested; `NotificationScheduler` turns it into notification requests.
//
//  iOS keeps at most 64 pending notifications per app, and repeating triggers can't stop on a
//  given date. So:
//  - Ongoing medications and measurement reminders use repeating triggers (daily, or weekly per
//    weekday). These are scheduled first.
//  - Courses (and medications starting in the future) use one-off triggers for each remaining
//    dose, soonest first, in whatever room is left. The app tops these up whenever it becomes
//    active; courses that didn't fit entirely are reported so the UI can say so.
//  - As-needed medications get no reminders.
//

import Foundation

struct PlannedReminder: Hashable {
    let identifier: String
    let title: String
    let body: String
    /// Hour and minute (plus weekday for weekly repeats, or the full date for one-offs).
    let dateComponents: DateComponents
    let repeats: Bool
    /// When a one-off fires; `nil` for repeating reminders.
    let fireDate: Date?
    let medicationID: Medication.ID?
}

struct ReminderPlan {
    var reminders: [PlannedReminder]
    /// Repeating reminders that didn't fit within the limit (they're never partially useful).
    var droppedRepeatingCount: Int
    /// Courses with remaining doses that didn't fit; their reminders end early until topped up.
    var coursesNotFullyScheduled: [Medication.ID]
    /// For each course not fully scheduled, the last dose that does have a reminder.
    var lastScheduledDose: [Medication.ID: Date]
}

enum ReminderPlanner {
    static let medicationPrefix = "med."
    static let measurementPrefix = "measure."
    static let systemPendingLimit = 64
    /// How far ahead to plan one-offs for an ongoing medication that starts in the future.
    static let futureStartHorizonDays = 30

    static func plan(
        medications: [Medication],
        measurementReminders: [MeasurementReminder],
        now: Date = .now,
        calendar: Calendar = .current,
        formatter: PrescriptionFormatter = PrescriptionFormatter(),
        limit: Int = systemPendingLimit
    ) -> ReminderPlan {
        let today = calendar.startOfDay(for: now)
        var repeating: [PlannedReminder] = []
        var oneOffs: [PlannedReminder] = []

        for medication in medications where !medication.schedule.isAsNeeded {
            let startsLater = calendar.startOfDay(for: medication.addedOn) > today
            if medication.course != nil || startsLater {
                oneOffs += datedReminders(for: medication, from: today, now: now, calendar: calendar, formatter: formatter)
            } else {
                repeating += repeatingReminders(for: medication, formatter: formatter)
            }
        }
        repeating += measurementReminders.filter(\.isEnabled).flatMap { measurementItems(for: $0) }

        let keptRepeating = Array(repeating.prefix(limit))
        let room = limit - keptRepeating.count
        let sortedOneOffs = oneOffs.sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
        let keptOneOffs = Array(sortedOneOffs.prefix(room))

        // Courses that lost some (later) doses, and the last dose that's still covered.
        let droppedOneOffs = sortedOneOffs.dropFirst(room)
        let incomplete = Set(droppedOneOffs.compactMap(\.medicationID))
        var lastScheduled: [Medication.ID: Date] = [:]
        for reminder in keptOneOffs {
            guard let id = reminder.medicationID, incomplete.contains(id), let date = reminder.fireDate else { continue }
            lastScheduled[id] = max(lastScheduled[id] ?? date, date)
        }

        return ReminderPlan(
            reminders: keptRepeating + keptOneOffs,
            droppedRepeatingCount: repeating.count - keptRepeating.count,
            coursesNotFullyScheduled: medications.map(\.id).filter(incomplete.contains),
            lastScheduledDose: lastScheduled
        )
    }

    // MARK: - Builders

    private static func repeatingReminders(for medication: Medication, formatter: PrescriptionFormatter) -> [PlannedReminder] {
        let title = "Time for \(medication.name)"
        let body = formatter.reminderBody(for: medication)
        let id = medication.id.uuidString

        if case .weekly(let days, _) = medication.schedule {
            return days.sorted().flatMap { day in
                medication.times.map { time in
                    var components = time.dateComponents
                    components.weekday = day.rawValue
                    return PlannedReminder(
                        identifier: "\(medicationPrefix)\(id).w\(day.rawValue).\(hhmm(time))",
                        title: title, body: body, dateComponents: components,
                        repeats: true, fireDate: nil, medicationID: medication.id
                    )
                }
            }
        }
        return medication.times.map { time in
            PlannedReminder(
                identifier: "\(medicationPrefix)\(id).\(hhmm(time))",
                title: title, body: body, dateComponents: time.dateComponents,
                repeats: true, fireDate: nil, medicationID: medication.id
            )
        }
    }

    /// One-off reminders for every remaining dose of a course, or for the first weeks of a
    /// medication that hasn't started yet.
    private static func datedReminders(
        for medication: Medication, from today: Date, now: Date, calendar: Calendar, formatter: PrescriptionFormatter
    ) -> [PlannedReminder] {
        let start = max(today, calendar.startOfDay(for: medication.course?.startDate ?? medication.addedOn))
        let lastDay: Date
        if let course = medication.course {
            lastDay = course.lastDay(calendar: calendar)
        } else {
            lastDay = calendar.date(byAdding: .day, value: futureStartHorizonDays - 1, to: start) ?? start
        }
        guard start <= lastDay else { return [] }

        let title = "Time for \(medication.name)"
        let baseBody = formatter.reminderBody(for: medication)
        var reminders: [PlannedReminder] = []
        var day = start
        while day <= lastDay {
            if medication.isScheduled(on: day, calendar: calendar) {
                let isLastDay = medication.course != nil && calendar.isDate(day, inSameDayAs: lastDay)
                let times = medication.times
                for (index, time) in times.enumerated() {
                    let fireDate = time.date(on: day, calendar: calendar)
                    guard fireDate > now else { continue }
                    var body = baseBody
                    if isLastDay {
                        body += index == times.count - 1
                            ? " This is the last dose of your course."
                            : " Last day of your course."
                    }
                    reminders.append(PlannedReminder(
                        identifier: "\(medicationPrefix)\(medication.id.uuidString).\(yyyymmdd(day, calendar: calendar)).\(hhmm(time))",
                        title: title, body: body,
                        dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                        repeats: false, fireDate: fireDate, medicationID: medication.id
                    ))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return reminders
    }

    private static func measurementItems(for reminder: MeasurementReminder) -> [PlannedReminder] {
        reminder.times.map { time in
            PlannedReminder(
                identifier: "\(measurementPrefix)\(reminder.kind.rawValue).\(hhmm(time))",
                title: "Measure your \(reminder.kind.label.lowercased())",
                body: "Time to take a reading.",
                dateComponents: time.dateComponents,
                repeats: true, fireDate: nil, medicationID: nil
            )
        }
    }

    private static func hhmm(_ time: TimeOfDay) -> String {
        String(format: "%02d%02d", time.hour, time.minute)
    }

    private static func yyyymmdd(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
