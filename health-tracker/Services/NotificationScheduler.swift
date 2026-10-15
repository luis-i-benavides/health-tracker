//
//  NotificationScheduler.swift
//  health-tracker
//

import Foundation
import UserNotifications

/// Schedules local notifications for medication doses and measurement reminders, following
/// the plan from `ReminderPlanner`. Identifiers are deterministic, so rescheduling replaces
/// existing requests rather than duplicating them.
struct NotificationScheduler {
    static let medicationPrefix = ReminderPlanner.medicationPrefix
    static let measurementPrefix = ReminderPlanner.measurementPrefix
    /// iOS keeps at most 64 pending local notifications per app.
    static let systemPendingLimit = ReminderPlanner.systemPendingLimit

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

    /// Sends a one-off notification after a short delay so the user can confirm reminders work.
    func sendTestNotification(after seconds: TimeInterval = 5) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Test reminder"
        content.body = "Notifications are working. Dose and measurement reminders will look like this."
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: "test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        ))
    }

    /// Identifiers and next fire dates of this app's pending reminders, soonest first.
    func pendingReminders() async -> [(id: String, title: String, next: Date?)] {
        await center.pendingNotificationRequests()
            .map { request in
                let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                return (request.identifier, request.content.title, next)
            }
            .sorted { ($0.next ?? .distantFuture) < ($1.next ?? .distantFuture) }
    }

    /// Replaces all medication and measurement notifications with the plan from `ReminderPlanner`,
    /// and returns the plan so callers can report courses whose reminders end early.
    @discardableResult
    func reschedule(medications: [Medication], measurementReminders: [MeasurementReminder]) async throws -> ReminderPlan {
        let plan = ReminderPlanner.plan(medications: medications, measurementReminders: measurementReminders)

        await removeAll(withPrefixes: [Self.medicationPrefix, Self.measurementPrefix])
        for reminder in plan.reminders {
            try await center.add(Self.request(for: reminder))
        }

        if plan.droppedRepeatingCount > 0 {
            throw SchedulingError.tooManyNotifications(
                requested: plan.reminders.count + plan.droppedRepeatingCount
            )
        }
        return plan
    }

    func removeAll(withPrefixes prefixes: [String]) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { id in
            prefixes.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Request builder

    static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        if let medicationID = reminder.medicationID {
            content.userInfo = ["medicationID": medicationID.uuidString]
        }
        return UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: reminder.dateComponents, repeats: reminder.repeats)
        )
    }
}
