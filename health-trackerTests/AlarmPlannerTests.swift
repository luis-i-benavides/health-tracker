//
//  AlarmPlannerTests.swift
//  health-trackerTests
//
//  Alarms: one per time for everything due then, repeating on the right days.
//

import Foundation
import Testing
import UserNotifications
@testable import health_tracker

/// Oct 12, 2026 is a Monday.
@MainActor
struct AlarmPlannerTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func medication(_ name: String, _ schedule: DoseSchedule, course: Course? = nil, addedOn: Date? = nil) -> Medication {
        Medication(name: name, strength: Strength(value: 10, unit: "mg"), schedule: schedule,
                   course: course, addedOn: addedOn ?? date(1))
    }

    private func plan(_ medications: [Medication], _ reminders: [MeasurementReminder] = []) -> [PlannedAlarm] {
        AlarmPlanner.plan(medications: medications, measurementReminders: reminders, now: date(12), calendar: calendar)
    }

    private let everyDay = Set(Weekday.allCases)

    @Test func medicationsAtTheSameTimeShareOneAlarm() {
        let alarms = plan([
            medication("Metformin", .daily(times: [t(8), t(20)])),
            medication("Lisinopril", .daily(times: [t(8)])),
        ])
        #expect(alarms.count == 2)
        #expect(alarms[0].time == t(8))
        #expect(alarms[0].medications == ["Metformin", "Lisinopril"])
        #expect(alarms[0].title == "Take Metformin, Lisinopril")
        #expect(alarms[0].isDaily)
        #expect(alarms[1].time == t(20))
        #expect(alarms[1].medications == ["Metformin"])
    }

    @Test func weeklyMedicationRepeatsOnItsDays() {
        let alarms = plan([medication("Methotrexate", .weekly(days: [.monday, .thursday], times: [t(9)]))])
        #expect(alarms.count == 1)
        #expect(alarms[0].weekdays == [.monday, .thursday])
        #expect(alarms[0].daysText == "Mon, Thu")
    }

    @Test func sameTimeOnDifferentDaysSplitsWithoutOverlap() {
        let alarms = plan([
            medication("Daily", .daily(times: [t(8)])),
            medication("Weekly", .weekly(days: [.monday], times: [t(8)])),
        ])
        #expect(alarms.count == 2)
        #expect(alarms[0].medications == ["Daily"])
        #expect(alarms[0].weekdays == everyDay.subtracting([.monday]))
        #expect(alarms[1].medications == ["Daily", "Weekly"])
        #expect(alarms[1].weekdays == [.monday])
        #expect(alarms[0].weekdays.isDisjoint(with: alarms[1].weekdays))
    }

    @Test func measurementsJoinMedicationAlarms() {
        let reminders = [
            MeasurementReminder(kind: .bloodPressure, times: [t(8)], isEnabled: true),
            MeasurementReminder(kind: .weight, times: [t(8)], isEnabled: false),
        ]
        let alarms = plan([medication("Lisinopril", .daily(times: [t(8)]))], reminders)
        #expect(alarms.count == 1)
        #expect(alarms[0].measurements == [.bloodPressure])
        #expect(alarms[0].title == "Take Lisinopril · Measure blood pressure")
    }

    @Test func asNeededMedicationsGetNoAlarms() {
        let alarms = plan([medication("Ibuprofen", .asNeeded(minHoursApart: 6, maxDosesPer24h: 4))])
        #expect(alarms.isEmpty)
    }

    @Test func courseEndingThisWeekOnlyRingsOnRemainingDays() {
        // Three days: Monday to Wednesday.
        let course = Course(startDate: date(12), days: 3, calendar: calendar)
        let alarms = plan([medication("Amoxicillin", .daily(times: [t(8)]), course: course, addedOn: date(12))])
        #expect(alarms.count == 1)
        #expect(alarms[0].weekdays == [.monday, .tuesday, .wednesday])
    }

    @Test func medicationStartingLaterThanAWeekGetsNoAlarmYet() {
        let alarms = plan([medication("Later", .daily(times: [t(8)]), addedOn: date(25))])
        #expect(alarms.isEmpty)
    }

    @Test func daysTextNamesCommonPatterns() {
        let weekdays = plan([medication("A", .weekly(days: [.monday, .tuesday, .wednesday, .thursday, .friday], times: [t(8)]))])
        #expect(weekdays.first?.daysText == "Weekdays")
        let daily = plan([medication("B", .daily(times: [t(8)]))])
        #expect(daily.first?.daysText == "Every day")
    }
}

/// Alarm settings are saved, and notifications go quiet while alarms ring instead.
@MainActor
struct AlarmSettingsTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "Alarm Settings Tests \(UUID().uuidString)")

    private var persistence: HealthPersistence {
        HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
    }

    @Test func alarmSettingsAreSavedAndReloaded() {
        let store = HealthStore(persistence: persistence)
        #expect(store.alarmSettings == .standard)
        #expect(!store.alarmSettings.isEnabled)

        store.alarmSettings = AlarmSettings(isEnabled: true, snoozeMinutes: 15, sound: .gentle)
        let reloaded = HealthStore(persistence: persistence)
        #expect(reloaded.alarmSettings == AlarmSettings(isEnabled: true, snoozeMinutes: 15, sound: .gentle))
    }

    @Test func dataSavedBeforeAlarmSettingsLoadsWithAlarmsOff() throws {
        var snapshot = HealthStore.preview.snapshot
        snapshot.alarmSettings = nil
        try persistence.save(snapshot)
        #expect(HealthStore(persistence: persistence).alarmSettings == .standard)
    }

    @Test func silentNotificationsHaveNoSound() {
        let reminder = PlannedReminder(
            identifier: "med.test", title: "Time for Test", body: "1 tablet",
            dateComponents: DateComponents(hour: 8, minute: 0), repeats: true, fireDate: nil, medicationID: nil
        )
        #expect(NotificationScheduler.request(for: reminder).content.sound != nil)
        let silent = NotificationScheduler.request(for: reminder, silent: true)
        #expect(silent.content.sound == nil)
        #expect(silent.content.title == "Time for Test")
    }

    @Test func soundsAreBundled() {
        for sound in AlarmSound.allCases {
            guard let fileName = sound.fileName else { continue }
            #expect(Bundle(for: HealthStore.self).url(forResource: fileName, withExtension: nil) != nil, "\(fileName)")
        }
    }
}
