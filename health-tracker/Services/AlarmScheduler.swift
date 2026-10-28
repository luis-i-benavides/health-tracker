//
//  AlarmScheduler.swift
//  health-tracker
//

import ActivityKit
import AlarmKit
import SwiftUI

/// Creates AlarmKit alarms from the plan from `AlarmPlanner`. Unlike notifications, these ring
/// through Silent mode and Focus, take over the Lock Screen, and can be snoozed. Apps can't add
/// alarms to the Clock app itself; AlarmKit alarms are the system-provided equivalent.
struct AlarmScheduler {
    enum SchedulingError: LocalizedError {
        case notAuthorized
        case tooManyAlarms(scheduled: Int, requested: Int)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Alarms aren't allowed. Turn them on in Settings › Health Tracker."
            case .tooManyAlarms(let scheduled, let requested):
                "iOS allowed only \(scheduled) of \(requested) alarms."
            }
        }
    }

    private var manager: AlarmManager { .shared }

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    /// Number of alarms this app currently has scheduled.
    func scheduledCount() -> Int {
        (try? manager.alarms.count) ?? 0
    }

    /// Whether any alarm is ringing, snoozed, or paused. Replacing alarms then would cut off
    /// a ringing alarm or lose a snooze, so callers wait until it's over.
    func hasAlarmInProgress() -> Bool {
        ((try? manager.alarms) ?? []).contains { $0.state != .scheduled }
    }

    /// Asks for permission if it hasn't been asked yet; throws if alarms aren't allowed.
    func requestAuthorization() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { throw SchedulingError.notAuthorized }
        default:
            throw SchedulingError.notAuthorized
        }
    }

    /// Replaces all of this app's alarms with `plan`. Returns how many were created.
    @discardableResult
    func replaceAll(with plan: [PlannedAlarm], settings: AlarmSettings) async throws -> Int {
        try await requestAuthorization()
        try removeAll()
        var created = 0
        for alarm in plan {
            do {
                _ = try await manager.schedule(id: UUID(), configuration: Self.configuration(for: alarm, settings: settings))
                created += 1
            } catch AlarmManager.AlarmError.maximumLimitReached {
                throw SchedulingError.tooManyAlarms(scheduled: created, requested: plan.count)
            }
        }
        return created
    }

    func removeAll() throws {
        for alarm in try manager.alarms {
            try manager.cancel(id: alarm.id)
        }
    }

    // MARK: - Configuration builder

    private static func configuration(
        for alarm: PlannedAlarm, settings: AlarmSettings
    ) -> AlarmManager.AlarmConfiguration<MedicationAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: "\(alarm.title)",
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        // Shown on the Lock Screen and in the Dynamic Island while snoozed.
        let snoozed = AlarmPresentation.Countdown(title: "Snoozed: \(alarm.title)", pauseButton: nil)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: snoozed, paused: nil),
            metadata: MedicationAlarmMetadata(label: alarm.title),
            tintColor: .blue
        )
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: alarm.time.hour, minute: alarm.time.minute),
            repeats: .weekly(alarm.weekdays.sorted().map(\.localeWeekday))
        ))
        return AlarmManager.AlarmConfiguration(
            // No countdown before the alarm; snoozing rings again after the snooze length.
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(settings.snoozeMinutes * 60)),
            schedule: schedule,
            attributes: attributes,
            sound: settings.sound.alertSound
        )
    }
}

private extension AlarmSound {
    var alertSound: AlertConfiguration.AlertSound {
        fileName.map { .named($0) } ?? .default
    }
}

private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
