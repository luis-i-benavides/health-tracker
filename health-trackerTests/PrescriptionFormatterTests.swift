//
//  PrescriptionFormatterTests.swift
//  health-trackerTests
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct PrescriptionFormatterTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var formatter: PrescriptionFormatter {
        PrescriptionFormatter(locale: Locale(identifier: "en_US"), calendar: calendar)
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    /// Time formatting uses a narrow no-break space before AM/PM; compare as plain spaces.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: - Instruction sentences

    @Test func antibioticCourse() {
        let amoxicillin = Medication(
            name: "Amoxicillin", strength: Strength(value: 500, unit: "mg"), form: .capsule,
            schedule: .daily(times: [t(8), t(14), t(20)]), foodRules: [.withFood],
            course: Course(startDate: .now, days: 10), purpose: "infection"
        )
        #expect(plain(formatter.instruction(for: amoxicillin)) ==
            "Take 1 capsule (500 mg) by mouth 3 times daily (8:00 AM, 2:00 PM, 8:00 PM) with food for 10 days for infection.")
        #expect(formatter.warnings(for: amoxicillin) ==
            ["Take every dose until the course is finished, even if you feel better."])
    }

    @Test func asNeededInhaler() {
        let albuterol = Medication(
            name: "Albuterol HFA", strength: Strength(value: 90, unit: "mcg"), form: .puff, quantity: 2,
            route: .inhaled, schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 4), purpose: "wheezing"
        )
        #expect(formatter.instruction(for: albuterol) ==
            "Inhale 2 puffs (180 mcg) as needed for wheezing, at least 4 hours apart.")
        #expect(formatter.warnings(for: albuterol) == ["No more than 8 puffs (4 doses) in 24 hours."])
    }

    @Test func asNeededSingleUnitWarningOmitsDoseCount() {
        let ibuprofen = Medication(
            name: "Ibuprofen", strength: Strength(value: 200, unit: "mg"),
            schedule: .asNeeded(minHoursApart: 6, maxDosesPer24h: 3)
        )
        #expect(formatter.warnings(for: ibuprofen) == ["No more than 3 tablets in 24 hours."])
        #expect(formatter.instruction(for: ibuprofen) == "Take 1 tablet (200 mg) by mouth as needed, at least 6 hours apart.")
    }

    @Test func multipleTabletsWithFoodAndAlcoholWarning() {
        let metformin = Medication(
            name: "Metformin", strength: Strength(value: 500, unit: "mg"), quantity: 2,
            schedule: .daily(times: [t(8), t(20)]), foodRules: [.withFood, .avoidAlcohol]
        )
        #expect(plain(formatter.instruction(for: metformin)) ==
            "Take 2 tablets (1,000 mg) by mouth twice daily (8:00 AM, 8:00 PM) with food.")
        #expect(formatter.warnings(for: metformin) == ["Avoid alcohol."])
    }

    @Test func splitTablets() {
        let half = Medication(name: "Metoprolol", strength: Strength(value: 25, unit: "mg"), quantity: 0.5,
                              schedule: .daily(times: [t(8)]))
        #expect(plain(formatter.instruction(for: half)) == "Take ½ tablet (12.5 mg) by mouth once daily (8:00 AM).")

        let oneAndHalf = Medication(name: "Warfarin", strength: Strength(value: 2, unit: "mg"), quantity: 1.5,
                                    schedule: .daily(times: [t(18)]))
        #expect(formatter.instruction(for: oneAndHalf).hasPrefix("Take 1½ tablets (3 mg) by mouth"))
    }

    @Test func smallStrengthsAreNotRounded() {
        let levothyroxine = Medication(name: "Levothyroxine", strength: Strength(parsing: "0.075 mg"),
                                       schedule: .daily(times: [t(6, 30)]), foodRules: [.emptyStomach])
        #expect(plain(formatter.instruction(for: levothyroxine)) ==
            "Take 1 tablet (0.075 mg) by mouth once daily (6:30 AM) on an empty stomach.")
        #expect(formatter.title(for: levothyroxine) == "Levothyroxine 0.075 mg tablet")
    }

    @Test func eyeDropsAtBedtime() {
        let latanoprost = Medication(name: "Latanoprost", strength: Strength(parsing: "0.005%"), form: .drop,
                                     route: .eye, schedule: .atBedtime(t(22)))
        #expect(plain(formatter.instruction(for: latanoprost)) ==
            "Instill 1 drop in the affected eye(s) at bedtime (10:00 PM).")
    }

    @Test func liquidUsesConcentrationForAmount() {
        let liquid = Medication(name: "Amoxicillin", strength: Strength(parsing: "250 mg/5 mL"), form: .milliliter,
                                quantity: 10, schedule: .daily(times: [t(8), t(20)]))
        #expect(plain(formatter.instruction(for: liquid)) ==
            "Take 10 mL (500 mg) by mouth twice daily (8:00 AM, 8:00 PM).")
        #expect(formatter.title(for: liquid) == "Amoxicillin 250 mg/5 mL")
    }

    @Test func topicalCream() {
        let cream = Medication(name: "Hydrocortisone", strength: Strength(parsing: "1%"), form: .application,
                               route: .topical, schedule: .daily(times: [t(8), t(20)]))
        #expect(plain(formatter.instruction(for: cream)) ==
            "Apply 1 application to the affected area twice daily (8:00 AM, 8:00 PM).")
    }

    @Test func insulinInjection() {
        let insulin = Medication(name: "Insulin glargine", strength: Strength(parsing: "100 units/mL"), form: .unit,
                                 quantity: 12, route: .subcutaneous, schedule: .atBedtime(t(22)))
        #expect(plain(formatter.instruction(for: insulin)) == "Inject 12 units under the skin at bedtime (10:00 PM).")
        #expect(formatter.title(for: insulin) == "Insulin glargine 100 units/mL")
    }

    @Test func everyEightHours() {
        let schedule = DoseSchedule.everyHours(interval: 8, firstDose: t(6))
        #expect(plain(formatter.scheduleText(schedule)) == "every 8 hours (6:00 AM, 2:00 PM, 10:00 PM)")
    }

    @Test func weeklyDaysAreListedMondayFirst() {
        let schedule = DoseSchedule.weekly(days: [.friday, .monday, .wednesday], times: [t(8)])
        #expect(plain(formatter.scheduleText(schedule)) == "on Monday, Wednesday, and Friday (8:00 AM)")

        let twiceWeekly = DoseSchedule.weekly(days: [.thursday, .monday], times: [t(20), t(8)])
        #expect(plain(formatter.scheduleText(twiceWeekly)) == "twice daily on Monday and Thursday (8:00 AM, 8:00 PM)")
    }

    @Test func shortMinimumIntervalIsShownInMinutes() {
        let schedule = DoseSchedule.asNeeded(minHoursApart: 0.5, maxDosesPer24h: 6)
        #expect(formatter.scheduleText(schedule) == "as needed, at least 30 minutes apart")
    }

    @Test func multipleInlineFoodRulesAreJoined() {
        let alendronate = Medication(name: "Alendronate", strength: Strength(value: 70, unit: "mg"),
                                     schedule: .weekly(days: [.sunday], times: [t(7)]),
                                     foodRules: [.fullGlassOfWater, .emptyStomach])
        #expect(plain(formatter.instruction(for: alendronate)) ==
            "Take 1 tablet (70 mg) by mouth on Sunday (7:00 AM) on an empty stomach and with a full glass of water.")
    }

    @Test func purposeIsNormalized() {
        let lisinopril = Medication(name: "Lisinopril", strength: Strength(value: 10, unit: "mg"),
                                    schedule: .daily(times: [t(8)]), purpose: "For blood pressure.")
        #expect(plain(formatter.instruction(for: lisinopril)) ==
            "Take 1 tablet (10 mg) by mouth once daily (8:00 AM) for blood pressure.")
    }

    @Test func tabletWithoutStrengthOmitsAmount() {
        let unknown = Medication(name: "Test", strength: nil, schedule: .daily(times: [t(8)]))
        #expect(plain(formatter.instruction(for: unknown)) == "Take 1 tablet by mouth once daily (8:00 AM).")
    }

    // MARK: - Titles and subtitles

    @Test func titleIncludesGenericNameAndSolidForm() {
        let brand = Medication(name: "Glucophage", genericName: "metformin", strength: Strength(value: 500, unit: "mg"),
                               schedule: .daily(times: [t(8)]))
        #expect(formatter.title(for: brand) == "Glucophage (metformin) 500 mg tablet")

        let inhaler = Medication(name: "Albuterol HFA", strength: Strength(value: 90, unit: "mcg"), form: .puff,
                                 route: .inhaled, schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 4))
        #expect(formatter.title(for: inhaler) == "Albuterol HFA 90 mcg")
    }

    @Test func subtitleShowsQuantityFoodAndCourseDay() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        let dayThree = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 14)))
        let amoxicillin = Medication(
            name: "Amoxicillin", strength: Strength(value: 500, unit: "mg"), form: .capsule,
            schedule: .daily(times: [t(8), t(14), t(20)]), foodRules: [.withFood, .avoidAlcohol],
            course: Course(startDate: start, days: 10, calendar: calendar)
        )
        #expect(formatter.subtitle(for: amoxicillin, on: dayThree) == "1 capsule · with food · day 3 of 10")
    }

    @Test func subtitleMarksAsNeeded() {
        let albuterol = Medication(name: "Albuterol HFA", strength: Strength(value: 90, unit: "mcg"), form: .puff,
                                   quantity: 2, route: .inhaled, schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 4))
        #expect(formatter.subtitle(for: albuterol, on: .now) == "2 puffs · as needed")
    }

    // MARK: - Pieces

    @Test(arguments: [
        (1.0, DoseForm.tablet, "1 tablet"),
        (2.0, .tablet, "2 tablets"),
        (0.5, .tablet, "½ tablet"),
        (0.25, .tablet, "¼ tablet"),
        (2.5, .tablet, "2½ tablets"),
        (0.3, .tablet, "0.3 tablet"),
        (7.5, .milliliter, "7.5 mL"),
        (2.0, .patch, "2 patches"),
        (1.0, .unit, "1 unit"),
    ])
    func quantities(quantity: Double, form: DoseForm, expected: String) {
        #expect(formatter.quantityText(quantity, form: form) == expected)
    }

    @Test func strengths() throws {
        #expect(formatter.strengthText(Strength(value: 500, unit: "mg")) == "500 mg")
        #expect(formatter.strengthText(try #require(Strength(parsing: "0.1%"))) == "0.1%")
        #expect(formatter.strengthText(try #require(Strength(parsing: "5 mg/5 mL"))) == "5 mg/5 mL")
        #expect(formatter.strengthText(try #require(Strength(parsing: "100 units/mL"))) == "100 units/mL")
    }
}
