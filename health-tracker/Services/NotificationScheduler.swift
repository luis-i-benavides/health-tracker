//
//  NotificationScheduler.swift
//  health-tracker
//

import Foundation
import UserNotifications

/// Schedules daily repeating local notifications for medication doses and measurement reminders.
///
/// Identifiers are deterministic (`med.<uuid>.<HHmm>`, `measure.<kind>.<HHmm>`), so rescheduling
/// replaces existing requests rather than duplicating them.
struct NotificationScheduler {
    static let medicationPrefix = "med."
    static let measurementPrefix = "measure."
    /// iOS keeps at most 64 pending local notifications per app.
    static let systemPendingLimit = 64

    enum SchedulingError: LocalizedError {
        case tooManyNotifications(requested: Int)

        var errorDescription: String? {
            switch self {
            case .tooManyNotifications(let requested):
                "iOS allows \(NotificationScheduler.systemPendingLimit) reminders, but \(requested) were requested. Only the first \(NotificationScheduler.systemPendingLimit) were scheduled."
            }
        }
    }

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Replaces all medication and measurement notifications with the given schedule.
    func reschedule(medications: [Medication], measurementReminders: [MeasurementReminder]) async throws {
        let requests = Self.medicationRequests(for: medications)
            + Self.measurementRequests(for: measurementReminders)

        await removeAll(withPrefixes: [Self.medicationPrefix, Self.measurementPrefix])

        for request in requests.prefix(Self.systemPendingLimit) {
            try await center.add(request)
        }

        if requests.count > Self.systemPendingLimit {
            throw SchedulingError.tooManyNotifications(requested: requests.count)
        }
    }

    func removeAll(withPrefixes prefixes: [String]) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { id in
            prefixes.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Request builders

    static func medicationRequests(for medications: [Medication]) -> [UNNotificationRequest] {
        medications.flatMap { medication in
            medication.times.map { time in
                let content = UNMutableNotificationContent()
                content.title = "Time for \(medication.name)"
                content.body = "Take \(medication.displayDosage) (scheduled \(time.formatted24h))."
                content.sound = .default
                content.userInfo = ["medicationID": medication.id.uuidString]

                return UNNotificationRequest(
                    identifier: "\(medicationPrefix)\(medication.id.uuidString).\(identifierSuffix(time))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: time.dateComponents, repeats: true)
                )
            }
        }
    }

    static func measurementRequests(for reminders: [MeasurementReminder]) -> [UNNotificationRequest] {
        reminders.filter(\.isEnabled).flatMap { reminder in
            reminder.times.map { time in
                let content = UNMutableNotificationContent()
                content.title = "Measure your \(reminder.kind.label.lowercased())"
                content.body = "It's \(time.formatted24h) — time to take a reading."
                content.sound = .default

                return UNNotificationRequest(
                    identifier: "\(measurementPrefix)\(reminder.kind.rawValue).\(identifierSuffix(time))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: time.dateComponents, repeats: true)
                )
            }
        }
    }

    private static func identifierSuffix(_ time: TimeOfDay) -> String {
        String(format: "%02d%02d", time.hour, time.minute)
    }
}
