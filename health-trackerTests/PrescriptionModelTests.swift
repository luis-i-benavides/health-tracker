//
//  PrescriptionModelTests.swift
//  health-trackerTests
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct StrengthTests {
    @Test(arguments: [
        ("500 mg", 500.0, "mg"),
        ("500mg", 500.0, "mg"),
        ("90 mcg", 90.0, "mcg"),
        ("90 µg", 90.0, "mcg"),
        ("0.075 mg", 0.075, "mg"),
        (".5 g", 0.5, "g"),
        ("1000 IU", 1000.0, "IU"),
        ("0.1%", 0.1, "%"),
        ("20 mEq", 20.0, "mEq"),
    ])
    func parsesAmountAndUnit(text: String, value: Double, unit: String) throws {
        let strength = try #require(Strength(parsing: text))
        #expect(strength.value == value)
        #expect(strength.unit == unit)
        #expect(strength.perVolume == nil)
    }

    @Test func parsesConcentrations() throws {
        let liquid = try #require(Strength(parsing: "250 mg/5 mL"))
        #expect(liquid.value == 250)
        #expect(liquid.unit == "mg")
        #expect(liquid.perVolume == 5)
        #expect(liquid.perVolumeUnit == "mL")

        let insulin = try #require(Strength(parsing: "100 units/mL"))
        #expect(insulin.unit == "units")
        #expect(insulin.perVolume == 1)
    }

    @Test(arguments: ["500", "mg", "abc", "500 furlongs", "", "5 mg/5 parsecs"])
    func rejectsInvalidStrengths(text: String) {
        #expect(Strength(parsing: text) == nil)
    }
}

@MainActor
struct VocabularyTests {
    @Test func parsesDoseForms() {
        #expect(DoseForm.parse("Tabs") == .tablet)
        #expect(DoseForm.parse("cap") == .capsule)
        #expect(DoseForm.parse("mL") == .milliliter)
        #expect(DoseForm.parse("puffs") == .puff)
        #expect(DoseForm.parse("gtt") == .drop)
        #expect(DoseForm.parse("cream") == .application)
        #expect(DoseForm.parse("widget") == nil)
    }

    @Test func parsesRoutesIncludingAbbreviations() {
        #expect(Route.parse("PO") == .byMouth)
        #expect(Route.parse("by mouth") == .byMouth)
        #expect(Route.parse("SL") == .sublingual)
        #expect(Route.parse("inhalation") == .inhaled)
        #expect(Route.parse("ophthalmic") == .eye)
        #expect(Route.parse("subq") == .subcutaneous)
        #expect(Route.parse("IM") == .intramuscular)
        #expect(Route.parse("teleport") == nil)
    }

    @Test func parsesFoodRules() {
        #expect(FoodRule.parse("With meals") == .withFood)
        #expect(FoodRule.parse("empty stomach") == .emptyStomach)
        #expect(FoodRule.parse("no alcohol") == .avoidAlcohol)
        #expect(FoodRule.parse("with chocolate") == nil)
    }

    @Test func parsesWeekdaysByUnambiguousPrefix() {
        #expect(Weekday.parse("Mon") == .monday)
        #expect(Weekday.parse("tues") == .tuesday)
        #expect(Weekday.parse("th") == .thursday)
        #expect(Weekday.parse("Sa") == .saturday)
        #expect(Weekday.parse("t") == nil)      // too short
        #expect(Weekday.parse("s") == nil)
        #expect(Weekday.parse("funday") == nil)
    }

    @Test func weekdaysSortMondayFirst() {
        #expect([Weekday.sunday, .friday, .monday].sorted() == [.monday, .friday, .sunday])
    }
}

@MainActor
struct ScheduleTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    @Test func everyHoursSpreadsAroundTheClock() {
        #expect(DoseSchedule.everyHours(interval: 8, firstDose: t(6)).times == [t(6), t(14), t(22)])
        // Wraps past midnight and stays sorted.
        #expect(DoseSchedule.everyHours(interval: 6, firstDose: t(9)).times == [t(3), t(9), t(15), t(21)])
        #expect(DoseSchedule.everyHours(interval: 12, firstDose: t(8, 30)).times == [t(8, 30), t(20, 30)])
    }

    @Test func dailyTimesAreSorted() {
        #expect(DoseSchedule.daily(times: [t(20), t(8)]).times == [t(8), t(20)])
    }

    @Test func asNeededHasNoScheduledTimesOrDays() {
        let schedule = DoseSchedule.asNeeded(minHoursApart: 4, maxDosesPer24h: 4)
        #expect(schedule.times.isEmpty)
        #expect(schedule.isAsNeeded)
        #expect(!schedule.isScheduled(on: .now, calendar: calendar))
    }

    @Test func weeklyIsOnlyScheduledOnItsDays() throws {
        let schedule = DoseSchedule.weekly(days: [.monday, .thursday], times: [t(8)])
        // 2026-10-12 is a Monday, 2026-10-13 a Tuesday, 2026-10-15 a Thursday.
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13)))
        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        #expect(schedule.isScheduled(on: monday, calendar: calendar))
        #expect(!schedule.isScheduled(on: tuesday, calendar: calendar))
        #expect(schedule.isScheduled(on: thursday, calendar: calendar))
    }
}

@MainActor
struct CourseTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func countsDaysInclusively() {
        // Started mid-afternoon; the course still begins at the start of that day.
        let course = Course(startDate: day(10, hour: 15), days: 10, calendar: calendar)
        #expect(course.startDate == day(10))
        #expect(course.dayNumber(on: day(10, hour: 9), calendar: calendar) == 1)
        #expect(course.dayNumber(on: day(12, hour: 23), calendar: calendar) == 3)
        #expect(course.dayNumber(on: day(19), calendar: calendar) == 10)
        #expect(course.lastDay(calendar: calendar) == day(19))
    }

    @Test func isInactiveOutsideTheCourse() {
        let course = Course(startDate: day(10), days: 10, calendar: calendar)
        #expect(!course.isActive(on: day(9, hour: 23), calendar: calendar))
        #expect(course.isActive(on: day(10), calendar: calendar))
        #expect(course.isActive(on: day(19, hour: 23), calendar: calendar))
        #expect(!course.isActive(on: day(20), calendar: calendar))
    }
}

@MainActor
struct MedicationTests {
    @Test func doseAmountMultipliesQuantityByStrength() throws {
        let metformin = Medication(name: "Metformin", strength: Strength(value: 500, unit: "mg"),
                                   quantity: 2, schedule: .daily(times: []))
        let amount = try #require(metformin.doseAmount)
        #expect(amount.value == 1000)
        #expect(amount.unit == "mg")
    }

    @Test func doseAmountForLiquidUsesConcentration() throws {
        let liquid = Medication(name: "Amoxicillin", strength: Strength(parsing: "250 mg/5 mL"),
                                form: .milliliter, quantity: 10, schedule: .daily(times: []))
        #expect(try #require(liquid.doseAmount).value == 500)
    }

    @Test func doseAmountIsUnavailableWhenItWouldBeMisleading() {
        // Percent strength: the amount per application isn't known.
        let cream = Medication(name: "Hydrocortisone", strength: Strength(value: 1, unit: "%"),
                               form: .application, route: .topical, schedule: .daily(times: []))
        #expect(cream.doseAmount == nil)
        // Insulin is dosed in units directly.
        let insulin = Medication(name: "Insulin glargine", strength: Strength(parsing: "100 units/mL"),
                                 form: .unit, quantity: 12, route: .subcutaneous, schedule: .daily(times: []))
        #expect(insulin.doseAmount == nil)
        // A concentration per mL can't be turned into an amount per drop.
        let drops = Medication(name: "Drops", strength: Strength(parsing: "5 mg/mL"),
                               form: .drop, route: .eye, schedule: .daily(times: []))
        #expect(drops.doseAmount == nil)
    }

    @Test func legacyInitTreatsDrugUnitsAsStrength() throws {
        let medication = Medication(name: "Lisinopril", dosage: 10, unit: "mg", times: [TimeOfDay(hour: 8, minute: 0)])
        #expect(medication.strength == Strength(value: 10, unit: "mg"))
        #expect(medication.form == .tablet)
        #expect(medication.quantity == 1)
        #expect(medication.route == .byMouth)
        #expect(PrescriptionFormatter(locale: Locale(identifier: "en_US")).doseText(for: medication) == "1 tablet (10 mg)")
    }

    @Test func legacyInitTreatsFormUnitsAsQuantity() {
        let medication = Medication(name: "Test", dosage: 2, unit: "tablets", times: [])
        #expect(medication.strength == nil)
        #expect(medication.form == .tablet)
        #expect(medication.quantity == 2)
        #expect(PrescriptionFormatter(locale: Locale(identifier: "en_US")).doseText(for: medication) == "2 tablets")
    }

    @Test func adoptingIdentityKeepsNewInstructions() {
        let old = Medication(name: "Lisinopril", dosage: 10, unit: "mg", times: [],
                             addedOn: Date(timeIntervalSince1970: 0))
        let new = Medication(name: "lisinopril", strength: Strength(value: 20, unit: "mg"),
                             schedule: .atBedtime(TimeOfDay(hour: 22, minute: 0)), foodRules: [.withFood])
        let merged = new.adoptingIdentity(of: old)
        #expect(merged.id == old.id)
        #expect(merged.addedOn == old.addedOn)
        #expect(merged.strength == new.strength)
        #expect(merged.schedule == new.schedule)
        #expect(merged.foodRules == [.withFood])
    }
}

@MainActor
struct GrainsAndPresetTests {
    @Test func grainsAreAStrengthUnit() throws {
        let strength = try #require(Strength(parsing: "5 gr"))
        #expect(strength.unit == "gr")
        #expect(Strength(parsing: "1 grain")?.unit == "gr")
        #expect(Strength(parsing: "5 grains")?.value == 5)
        // Grams stay grams.
        #expect(Strength(parsing: "1 g")?.unit == "g")
        #expect(PrescriptionFormatter().strengthText(strength) == "5 gr")
    }

    @Test func csvImportAcceptsGrains() {
        let result = CSVMedicationParser.parse("""
        name,strength,form,quantity,frequency
        Aspirin,5 gr,tablet,1,once daily
        """)
        #expect(result.errors.isEmpty)
        #expect(result.medications.first?.strength?.unit == "gr")
    }

    @Test func presetsUseMealTimes() {
        let meals = MealTimes.standard
        #expect(meals.doseTimes(perDay: 1) == [meals.breakfast])
        #expect(meals.doseTimes(perDay: 2) == [meals.breakfast, meals.dinner])
        #expect(meals.doseTimes(perDay: 3) == [meals.breakfast, meals.lunch, meals.dinner])
        #expect(meals.doseTimes(perDay: 4) == [meals.breakfast, meals.lunch, meals.dinner, meals.bedtime])
    }
}

@MainActor
struct PainLocationTests {
    @Test func painTypesTakeABodyPart() {
        let log = SymptomLog(type: .neuropathicPain, bodyPart: .legs, severity: .moderate)
        #expect(log.displayName == "Neuropathic pain (legs)")
        #expect(SymptomLog(type: .jointPain, bodyPart: .lowerBack, severity: .mild).displayName == "Joint pain (lower back)")
        #expect(SymptomLog(type: .nociceptivePain, severity: .mild).displayName == "Nociceptive pain")
    }

    @Test func otherSymptomsIgnoreABodyPart() {
        #expect(SymptomLog(type: .headache, bodyPart: .arms, severity: .mild).bodyPart == nil)
    }

    @Test func bodyPartRoundTripsAndOlderDataStillLoads() throws {
        let log = SymptomLog(type: .nociceptivePain, bodyPart: .upperBack, severity: .severe)
        let decoded = try JSONDecoder().decode(SymptomLog.self, from: JSONEncoder().encode(log))
        #expect(decoded.bodyPart == .upperBack)

        // A symptom saved before body parts existed has no "bodyPart" key.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as? [String: Any])
        json["bodyPart"] = nil
        let old = try JSONDecoder().decode(SymptomLog.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.bodyPart == nil)
    }
}
