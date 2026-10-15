//
//  SchedulingTests.swift
//  health-trackerTests
//
//  Phase 2: which doses are due on a day, as-needed limits over a rolling 24 hours,
//  and the notification plan within iOS's 64-reminder limit.
//

import Foundation
import Testing
@testable import health_tracker

/// Shared helpers: a fixed calendar and dates in October 2026 (Oct 12 is a Monday).
@MainActor
private enum Fixture {
    static let calendar = Calendar(identifier: .gregorian)

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    static func medication(
        _ name: String = "Test", schedule: DoseSchedule, course: Course? = nil, addedOn: Date? = nil
    ) -> Medication {
        Medication(name: name, strength: Strength(value: 10, unit: "mg"), schedule: schedule,
                   course: course, addedOn: addedOn ?? date(1))
    }

    static func log(_ medication: Medication, at takenAt: Date, status: DoseStatus = .taken) -> MedicationLog {
        MedicationLog(medicationID: medication.id, scheduledTime: nil, takenAt: takenAt,
                      quantityTaken: 1, status: status)
    }
}

// MARK: - Doses due on a day

@MainActor
struct DoseScheduleRulesTests {
    private typealias F = Fixture

    private func doseCount(_ medication: Medication, on day: Date) -> Int {
        HealthStore(medications: [medication]).doses(on: day, calendar: F.calendar).count
    }

    @Test func courseOnlyHasDosesWithinItsDays() {
        let course = Course(startDate: F.date(10), days: 3, calendar: F.calendar)
        let med = F.medication(schedule: .daily(times: [F.t(8), F.t(20)]), course: course, addedOn: F.date(10))
        #expect(doseCount(med, on: F.date(9)) == 0)
        #expect(doseCount(med, on: F.date(10)) == 2)
        #expect(doseCount(med, on: F.date(12)) == 2)   // last day
        #expect(doseCount(med, on: F.date(13)) == 0)
    }

    @Test func weeklyOnlyOnItsDays() {
        let med = F.medication(schedule: .weekly(days: [.monday, .thursday], times: [F.t(8)]))
        #expect(doseCount(med, on: F.date(12)) == 1)   // Monday
        #expect(doseCount(med, on: F.date(13)) == 0)   // Tuesday
        #expect(doseCount(med, on: F.date(15)) == 1)   // Thursday
    }

    @Test func asNeededHasNoScheduledDoses() {
        let med = F.medication(schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 4))
        #expect(doseCount(med, on: F.date(12)) == 0)
    }

    @Test func nothingBeforeTheMedicationWasAdded() {
        let med = F.medication(schedule: .daily(times: [F.t(8)]), addedOn: F.date(12, 15))
        #expect(doseCount(med, on: F.date(11)) == 0)
        #expect(doseCount(med, on: F.date(12)) == 1)
    }

    @Test func everyEightHoursHasThreeSlots() {
        let med = F.medication(schedule: .everyHours(interval: 8, firstDose: F.t(6)))
        let slots = HealthStore(medications: [med]).doses(on: F.date(12), calendar: F.calendar)
        #expect(slots.map(\.date) == [F.date(12, 6), F.date(12, 14), F.date(12, 22)])
    }
}

// MARK: - As-needed limits

@MainActor
struct AsNeededLimitTests {
    private typealias F = Fixture
    private let inhaler = F.medication("Albuterol", schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 3))

    @Test func countsDosesInTheLast24HoursOnly() throws {
        let logs = [
            F.log(inhaler, at: F.date(11, 7)),    // 25 hours before: outside the window
            F.log(inhaler, at: F.date(11, 23)),   // 9 hours before: counts
            F.log(inhaler, at: F.date(12, 6)),
        ]
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: logs, at: F.date(12, 8)))
        #expect(status.dosesInLast24h == 2)
        #expect(status.remainingDoses == 1)
        #expect(status.lastDose == F.date(12, 6))
    }

    @Test func lateNightDoseStillCountsNextMorning() throws {
        // Rolling window, not calendar day: an 11 PM dose counts at 8 AM.
        let logs = [F.log(inhaler, at: F.date(11, 23))]
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: logs, at: F.date(12, 8)))
        #expect(status.dosesInLast24h == 1)
    }

    @Test func skippedAndFutureLogsDoNotCount() throws {
        let logs = [
            F.log(inhaler, at: F.date(12, 6), status: .skipped),
            F.log(inhaler, at: F.date(12, 10)),   // after `time`
        ]
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: logs, at: F.date(12, 8)))
        #expect(status.dosesInLast24h == 0)
        #expect(status.lastDose == nil)
        #expect(status.nextAllowed == nil)
    }

    @Test func otherMedicationsDoNotCount() throws {
        let other = F.medication("Other", schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 3))
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: [F.log(other, at: F.date(12, 7))], at: F.date(12, 8)))
        #expect(status.dosesInLast24h == 0)
    }

    @Test func nextAllowedRespectsTheMinimumGap() throws {
        let logs = [F.log(inhaler, at: F.date(12, 6))]
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: logs, at: F.date(12, 8)))
        #expect(status.nextAllowed == F.date(12, 10))
    }

    @Test func nextAllowedWaitsForTheOldestDoseToRollOff() throws {
        // At the 3-dose maximum: the 1 AM dose leaves the window at 1 AM tomorrow.
        let logs = [F.date(12, 1), F.date(12, 6), F.date(12, 11)].map { F.log(inhaler, at: $0) }
        let status = try #require(AsNeededLimits.status(for: inhaler, logs: logs, at: F.date(12, 20)))
        #expect(status.remainingDoses == 0)
        #expect(status.nextAllowed == F.date(13, 1))
    }

    @Test func noWarningsWithinLimits() {
        let logs = [F.log(inhaler, at: F.date(12, 2))]
        #expect(AsNeededLimits.warnings(forDoseOf: inhaler, logs: logs, at: F.date(12, 8)).isEmpty)
    }

    @Test func warnsWhenOverTheDailyMaximum() {
        let logs = [F.date(12, 1), F.date(12, 6), F.date(12, 11)].map { F.log(inhaler, at: $0) }
        let warnings = AsNeededLimits.warnings(forDoseOf: inhaler, logs: logs, at: F.date(12, 20))
        #expect(warnings == [.overDailyMax(count: 4, max: 3)])
    }

    @Test func warnsWhenTooSoon() {
        let logs = [F.log(inhaler, at: F.date(12, 6))]
        let warnings = AsNeededLimits.warnings(forDoseOf: inhaler, logs: logs, at: F.date(12, 8))
        #expect(warnings == [.tooSoon(lastDose: F.date(12, 6), nextAllowed: F.date(12, 10))])
    }

    @Test func canWarnForBothAtOnce() {
        let logs = [F.date(12, 1), F.date(12, 6), F.date(12, 11)].map { F.log(inhaler, at: $0) }
        let warnings = AsNeededLimits.warnings(forDoseOf: inhaler, logs: logs, at: F.date(12, 12))
        #expect(warnings.count == 2)
    }

    @Test func scheduledMedicationsHaveNoLimits() {
        let daily = F.medication(schedule: .daily(times: [F.t(8)]))
        #expect(AsNeededLimits.status(for: daily, logs: [], at: F.date(12)) == nil)
        #expect(AsNeededLimits.warnings(forDoseOf: daily, logs: [], at: F.date(12)).isEmpty)
    }
}

// MARK: - Notification plan

@MainActor
struct ReminderPlannerTests {
    private typealias F = Fixture
    private let formatter = PrescriptionFormatter(locale: Locale(identifier: "en_US"), calendar: Fixture.calendar)

    private func plan(_ medications: [Medication], measurements: [MeasurementReminder] = [],
                      now: Date, limit: Int = 64) -> ReminderPlan {
        ReminderPlanner.plan(medications: medications, measurementReminders: measurements,
                             now: now, calendar: F.calendar, formatter: formatter, limit: limit)
    }

    @Test func ongoingDailyMedicationRepeats() throws {
        let med = F.medication("Metformin", schedule: .daily(times: [F.t(8), F.t(20)]))
        let reminders = plan([med], now: F.date(12, 9)).reminders
        #expect(reminders.count == 2)
        #expect(reminders.allSatisfy { $0.repeats })
        #expect(reminders.map(\.dateComponents) == [DateComponents(hour: 8, minute: 0), DateComponents(hour: 20, minute: 0)])
        let first = try #require(reminders.first)
        #expect(first.title == "Time for Metformin")
        #expect(first.body == "Take 1 tablet (10 mg) by mouth.")
        #expect(first.identifier == "med.\(med.id.uuidString).0800")
    }

    @Test func weeklyRepeatsPerWeekday() {
        let med = F.medication(schedule: .weekly(days: [.thursday, .monday], times: [F.t(9)]))
        let reminders = plan([med], now: F.date(12)).reminders
        #expect(reminders.map(\.dateComponents.weekday) == [Weekday.monday.rawValue, Weekday.thursday.rawValue])
        #expect(reminders.allSatisfy { $0.repeats && $0.dateComponents.hour == 9 })
    }

    @Test func asNeededHasNoReminders() {
        let med = F.medication(schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 4))
        #expect(plan([med], now: F.date(12)).reminders.isEmpty)
    }

    @Test func courseGetsOneOffsForRemainingDosesOnly() {
        // 3-day course, twice daily, starting Oct 12; it's 9 AM on day 1, so 8 AM has passed.
        let course = Course(startDate: F.date(12), days: 3, calendar: F.calendar)
        let med = F.medication(schedule: .daily(times: [F.t(8), F.t(20)]), course: course, addedOn: F.date(12))
        let reminders = plan([med], now: F.date(12, 9)).reminders
        #expect(reminders.map(\.fireDate) == [F.date(12, 20), F.date(13, 8), F.date(13, 20), F.date(14, 8), F.date(14, 20)])
        #expect(reminders.allSatisfy { !$0.repeats })
        #expect(reminders.first?.identifier == "med.\(med.id.uuidString).20261012.2000")
    }

    @Test func lastDayRemindersSaySo() {
        let course = Course(startDate: F.date(12), days: 2, calendar: F.calendar)
        let med = F.medication(schedule: .daily(times: [F.t(8), F.t(20)]), course: course, addedOn: F.date(12))
        let bodies = plan([med], now: F.date(12)).reminders.map(\.body)
        #expect(bodies == [
            "Take 1 tablet (10 mg) by mouth.",
            "Take 1 tablet (10 mg) by mouth.",
            "Take 1 tablet (10 mg) by mouth. Last day of your course.",
            "Take 1 tablet (10 mg) by mouth. This is the last dose of your course.",
        ])
    }

    @Test func finishedCourseHasNoReminders() {
        let course = Course(startDate: F.date(1), days: 5, calendar: F.calendar)
        let med = F.medication(schedule: .daily(times: [F.t(8)]), course: course)
        #expect(plan([med], now: F.date(12)).reminders.isEmpty)
    }

    @Test func futureStartUsesOneOffsFromTheStartDay() {
        let med = F.medication(schedule: .daily(times: [F.t(8)]), addedOn: F.date(20))
        let reminders = plan([med], now: F.date(12)).reminders
        #expect(reminders.count == ReminderPlanner.futureStartHorizonDays)
        #expect(reminders.first?.fireDate == F.date(20, 8))
        #expect(reminders.allSatisfy { !$0.repeats })
    }

    @Test func measurementRemindersRepeatDaily() {
        let bp = MeasurementReminder(kind: .bloodPressure, times: [F.t(7, 30)], isEnabled: true)
        let off = MeasurementReminder(kind: .weight, times: [F.t(6)], isEnabled: false)
        let reminders = plan([], measurements: [bp, off], now: F.date(12)).reminders
        #expect(reminders.map(\.identifier) == ["measure.bloodPressure.0730"])
        #expect(reminders.first?.title == "Measure your blood pressure")
    }

    @Test func repeatingRemindersAreKeptBeforeCourseDoses() {
        // Limit of 5: 2 repeating + the 3 soonest course doses; the rest are reported.
        let ongoing = F.medication("Ongoing", schedule: .daily(times: [F.t(8), F.t(20)]))
        let course = Course(startDate: F.date(12), days: 10, calendar: F.calendar)
        let antibiotic = F.medication("Antibiotic", schedule: .daily(times: [F.t(8), F.t(14), F.t(20)]),
                                      course: course, addedOn: F.date(12))
        let result = plan([ongoing, antibiotic], now: F.date(12), limit: 5)
        #expect(result.reminders.count == 5)
        #expect(result.reminders.filter(\.repeats).count == 2)
        #expect(result.reminders.compactMap(\.fireDate) == [F.date(12, 8), F.date(12, 14), F.date(12, 20)])
        #expect(result.coursesNotFullyScheduled == [antibiotic.id])
        #expect(result.lastScheduledDose[antibiotic.id] == F.date(12, 20))
        #expect(result.droppedRepeatingCount == 0)
    }

    @Test func soonestCourseDosesWinAcrossCourses() {
        let first = F.medication("A", schedule: .daily(times: [F.t(9)]),
                                 course: Course(startDate: F.date(12), days: 5, calendar: F.calendar), addedOn: F.date(12))
        let second = F.medication("B", schedule: .daily(times: [F.t(10)]),
                                  course: Course(startDate: F.date(12), days: 5, calendar: F.calendar), addedOn: F.date(12))
        let result = plan([first, second], now: F.date(12), limit: 4)
        #expect(result.reminders.compactMap(\.fireDate) == [F.date(12, 9), F.date(12, 10), F.date(13, 9), F.date(13, 10)])
        #expect(Set(result.coursesNotFullyScheduled) == [first.id, second.id])
    }

    @Test func tooManyRepeatingRemindersAreReported() {
        let many = (0..<3).map { F.medication("M\($0)", schedule: .daily(times: [F.t(8), F.t(12), F.t(20)])) }
        let result = plan(many, now: F.date(12), limit: 5)
        #expect(result.reminders.count == 5)
        #expect(result.droppedRepeatingCount == 4)
    }

    @Test func reminderBodyIncludesRouteAndFood() {
        let amoxicillin = Medication(name: "Amoxicillin", strength: Strength(value: 500, unit: "mg"), form: .capsule,
                                     schedule: .daily(times: [F.t(8)]), foodRules: [.withFood, .avoidAlcohol])
        #expect(formatter.reminderBody(for: amoxicillin) == "Take 1 capsule (500 mg) by mouth with food.")
    }
}
