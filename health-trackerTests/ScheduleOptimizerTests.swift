//
//  ScheduleOptimizerTests.swift
//  health-trackerTests
//
//  Request building, response handling and suggestion checks. No network calls.
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct ScheduleOptimizerRequestTests {
    @Test func requestUsesStructuredOutputAndFallbacks() throws {
        let body = ScheduleOptimizer.requestBody(prompt: "Hello")
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "adaptive")
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "high")
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        // The body must serialize to JSON as-is.
        #expect(throws: Never.self) { try JSONSerialization.data(withJSONObject: body) }
    }

    @Test func promptDescribesEachMedicationAndRoutine() {
        let keyed = ScheduleOptimizer.keyed(SampleData.medications)
        let symptoms = [SymptomLog(type: .nausea, severity: .moderate, date: TimeOfDay(hour: 9, minute: 10).date())]
        let prompt = ScheduleOptimizer.prompt(keyed: keyed, mealTimes: .standard, preferences: .standard, symptoms: symptoms)

        #expect(prompt.contains("breakfast 08:00"))
        #expect(prompt.contains("key: m2"))
        #expect(prompt.contains("name: Metformin"))
        #expect(prompt.contains("2× daily, currently 08:00, 20:00 — choose 2 time(s)"))
        #expect(prompt.contains("with food"))
        // Albuterol is listed as as-needed, not scheduled.
        let asNeededPart = prompt.components(separatedBy: "As needed (not scheduled):").last ?? ""
        #expect(asNeededPart.contains("Albuterol"))
        #expect(prompt.contains("- Nausea: 1 time(s) (worst: moderate), at 09:10"))
        // No instructions, no section.
        #expect(!prompt.contains("Additional instructions"))
    }

    @Test func promptIncludesTrimmedInstructions() {
        let keyed = ScheduleOptimizer.keyed(SampleData.medications)
        let prompt = ScheduleOptimizer.prompt(keyed: keyed, mealTimes: .standard, preferences: .standard,
                                              symptoms: [], instructions: "  I walk at 18:00.\n")
        #expect(prompt.hasSuffix("Additional instructions from the patient:\nI walk at 18:00."))

        let blank = ScheduleOptimizer.prompt(keyed: keyed, mealTimes: .standard, preferences: .standard,
                                             symptoms: [], instructions: " \n ")
        #expect(!blank.contains("Additional instructions"))
    }

    @Test func finishedCoursesAreLeftOut() {
        let finished = Medication(
            name: "Old antibiotic", strength: nil, schedule: .daily(times: [TimeOfDay(hour: 8, minute: 0)]),
            course: Course(startDate: .now.addingTimeInterval(-30 * 86_400), days: 5)
        )
        let included = ScheduleOptimizer.medicationsToSchedule([finished, SampleData.amoxicillin], today: .now)
        #expect(included.map(\.name) == [SampleData.amoxicillin.name])
    }
}

@MainActor
struct ScheduleOptimizerResponseTests {
    private func response(stopReason: String = "end_turn", text: String) -> Data {
        let json: [String: Any] = [
            "stop_reason": stopReason,
            "content": [
                ["type": "thinking", "thinking": ""],
                ["type": "text", "text": text],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private let validAnswer = """
    {"summary":"Fewer times.","medications":[{"key":"m1","times":["08:00"],"takeWithFood":true,"reason":"Breakfast."}],
     "warnings":[{"severity":"caution","message":"Watch for nausea.","medicationKeys":["m1"]}]}
    """

    @Test func readsTheTextBlockAndSkipsThinking() throws {
        let suggestion = try ScheduleOptimizer.decodeResponse(response(text: validAnswer), status: 200)
        #expect(suggestion.summary == "Fewer times.")
        #expect(suggestion.medications.first?.takeWithFood == true)
        #expect(suggestion.warnings.first?.severity == .caution)
    }

    @Test func refusalAndTruncationAreReported() {
        #expect(throws: ScheduleOptimizerError.refused) {
            try ScheduleOptimizer.decodeResponse(response(stopReason: "refusal", text: ""), status: 200)
        }
        #expect(throws: ScheduleOptimizerError.truncated) {
            try ScheduleOptimizer.decodeResponse(response(stopReason: "max_tokens", text: "{"), status: 200)
        }
        #expect(throws: ScheduleOptimizerError.malformedResponse) {
            try ScheduleOptimizer.decodeResponse(response(text: "not json"), status: 200)
        }
    }

    @Test func httpErrorsMapToMessages() {
        let error = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"Bad schema"}}"#.utf8)
        #expect(throws: ScheduleOptimizerError.invalidAPIKey) { try ScheduleOptimizer.decodeResponse(error, status: 401) }
        #expect(throws: ScheduleOptimizerError.rateLimited) { try ScheduleOptimizer.decodeResponse(error, status: 429) }
        #expect(throws: ScheduleOptimizerError.overloaded) { try ScheduleOptimizer.decodeResponse(error, status: 529) }
        #expect(throws: ScheduleOptimizerError.server(status: 400, message: "Bad schema")) {
            try ScheduleOptimizer.decodeResponse(error, status: 400)
        }
    }
}

@MainActor
struct ScheduleSuggestionCheckTests {
    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func entry(_ times: [String], withFood: Bool = false) -> ScheduleSuggestion.MedicationTimes {
        .init(key: "m1", times: times, takeWithFood: withFood, reason: "Because.")
    }

    private func check(_ medication: Medication, _ times: [String], withFood: Bool = false) -> ProposedScheduleChange {
        ScheduleOptimizer.checkedChange(for: medication, entry: entry(times, withFood: withFood), mealTimes: .standard, preferences: .standard)
    }

    @Test func dailyTimesAreReplaced() {
        let change = check(SampleData.metformin, ["19:00", "08:00"])
        #expect(change.problem == nil)
        #expect(change.schedule == .daily(times: [t(8), t(19)]))
        #expect(change.changesSomething)
    }

    @Test func changingTheNumberOfDosesIsRejected() {
        let change = check(SampleData.metformin, ["08:00"])
        #expect(change.problem != nil)
        #expect(change.schedule == SampleData.metformin.schedule)
        #expect(!change.changesSomething)
    }

    @Test func invalidOrRepeatedTimesAreRejected() {
        #expect(check(SampleData.metformin, ["8am", "20:00"]).problem != nil)
        #expect(check(SampleData.metformin, ["08:00", "08:00"]).problem != nil)
    }

    @Test func everyHoursMustKeepItsInterval() {
        let medication = Medication(name: "Q8H", strength: nil,
                                    schedule: .everyHours(interval: 8, firstDose: t(6)))
        let good = check(medication, ["07:00", "15:00", "23:00"])
        #expect(good.problem == nil)
        #expect(good.schedule == .everyHours(interval: 8, firstDose: t(7)))
        #expect(check(medication, ["07:00", "14:00", "23:00"]).problem != nil)
    }

    @Test func weeklyKeepsItsDaysAndBedtimeStaysBedtime() {
        let weekly = Medication(name: "Weekly", strength: nil,
                                schedule: .weekly(days: [.monday, .thursday], times: [t(9)]))
        #expect(check(weekly, ["08:00"]).schedule == .weekly(days: [.monday, .thursday], times: [t(8)]))
        #expect(check(SampleData.atorvastatin, ["22:30"]).schedule == .atBedtime(t(22, 30)))
    }

    @Test func withFoodIsNotAddedOverAnEmptyStomachRule() {
        let fasting = Medication(name: "Levothyroxine", strength: nil,
                                 schedule: .daily(times: [t(6)]), foodRules: [.emptyStomach])
        #expect(!check(fasting, ["06:30"], withFood: true).addsWithFood)
        #expect(check(SampleData.lisinopril, ["08:00"], withFood: true).addsWithFood)
        // Already with food: nothing to add.
        #expect(!check(SampleData.vitaminD, ["12:30"], withFood: true).addsWithFood)
    }

    @Test func withFoodDoseAwayFromMealsGetsANote() {
        #expect(check(SampleData.vitaminD, ["15:00"]).notes.count == 1)
        #expect(check(SampleData.vitaminD, ["12:30"]).notes.isEmpty)
    }

    @Test func missingSuggestionKeepsCurrentTimes() {
        let suggestion = ScheduleSuggestion(summary: "", medications: [], warnings: [])
        let proposal = ScheduleOptimizer.proposal(
            from: suggestion, keyed: ScheduleOptimizer.keyed([SampleData.lisinopril]), mealTimes: .standard, preferences: .standard
        )
        #expect(proposal.changes.first?.problem != nil)
        #expect(!proposal.hasChanges)
    }

    @Test func sampleProposalReducesDoseTimes() {
        let proposal = SampleData.scheduleProposal
        #expect(proposal.distinctTimesBefore == 6)
        #expect(proposal.distinctTimesAfter == 4)
        #expect(proposal.changes.allSatisfy { $0.problem == nil })
        // As-needed albuterol isn't part of the schedule; the warning names amoxicillin.
        #expect(!proposal.changes.contains { $0.medication.id == SampleData.albuterol.id })
        #expect(proposal.warnings.first?.medicationNames == [SampleData.amoxicillin.name])
    }

    @Test func applyingUpdatesSchedulesAndFoodRules() {
        let store = HealthStore(medications: [SampleData.lisinopril, SampleData.metformin])
        let suggestion = ScheduleSuggestion(
            summary: "",
            medications: [
                .init(key: "m1", times: ["08:00"], takeWithFood: true, reason: ""),
                .init(key: "m2", times: ["08:00", "19:00"], takeWithFood: false, reason: ""),
            ],
            warnings: []
        )
        let proposal = ScheduleOptimizer.proposal(
            from: suggestion, keyed: ScheduleOptimizer.keyed(store.medications), mealTimes: .standard, preferences: .standard
        )
        store.applyChanges(of: proposal)
        #expect(store.medications[0].foodRules.contains(.withFood))
        #expect(store.medications[1].times == [t(8), t(19)])
    }
}

@MainActor
struct MedicationEditingTests {
    @Test func medicationsCanBeAddedUpdatedAndDeleted() {
        let store = HealthStore(medications: [SampleData.lisinopril])
        store.addMedication(SampleData.metformin)
        #expect(store.medications.count == 2)

        var edited = SampleData.metformin
        edited.quantity = 2
        store.updateMedication(edited)
        #expect(store.medications[1].quantity == 2)

        store.logDose(MedicationLog(medicationID: SampleData.metformin.id, scheduledTime: nil,
                                    quantityTaken: 1, status: .extra))
        #expect(store.logCount(for: SampleData.metformin.id) == 1)
        store.deleteMedication(id: SampleData.metformin.id)
        #expect(store.medications.map(\.id) == [SampleData.lisinopril.id])
        #expect(store.medicationLogs.isEmpty)
    }

    @Test func mealTimesAreSaved() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Meal Times Tests \(UUID().uuidString)")
        let persistence = HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
        let store = HealthStore(persistence: persistence)
        #expect(store.mealTimes == .standard)
        store.mealTimes.dinner = TimeOfDay(hour: 18, minute: 15)

        let reopened = HealthStore(persistence: persistence)
        #expect(reopened.mealTimes.dinner == TimeOfDay(hour: 18, minute: 15))
    }

    @Test func mealMatchingUsesATolerance() {
        let meals = MealTimes.standard
        #expect(meals.meal(near: TimeOfDay(hour: 8, minute: 20)) == "breakfast")
        #expect(meals.meal(near: TimeOfDay(hour: 10, minute: 0)) == nil)
    }
}

@MainActor
struct SchedulePreferenceTests {
    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private var busy: SchedulePreferences {
        SchedulePreferences(
            coffeeTime: t(7, 30), dairyMeals: [.breakfast, .dinner],
            workHours: TimeWindow(start: t(9), end: t(17)), avoidSleepHours: true, timePreference: .morning
        )
    }

    @Test func windowsCanWrapPastMidnight() {
        let day = TimeWindow(start: t(9), end: t(17))
        #expect(day.contains(t(9)))
        #expect(!day.contains(t(17)))
        let night = TimeWindow(start: t(22), end: t(6))
        #expect(night.contains(t(23)))
        #expect(night.contains(t(2)))
        #expect(!night.contains(t(12)))
    }

    @Test func conflictsWithWorkAndSleepHours() {
        let meals = MealTimes.standard
        #expect(busy.conflict(for: t(12), mealTimes: meals) == "during your work hours")
        #expect(busy.conflict(for: t(2), mealTimes: meals) == "during your sleep hours")
        #expect(busy.conflict(for: t(8), mealTimes: meals) == nil)
        var relaxed = busy
        relaxed.avoidSleepHours = false
        relaxed.workHours = nil
        #expect(relaxed.conflict(for: t(2), mealTimes: meals) == nil)
    }

    @Test func promptListsEachPreference() {
        let prompt = ScheduleOptimizer.prompt(
            keyed: ScheduleOptimizer.keyed([SampleData.lisinopril]), mealTimes: .standard, preferences: busy, symptoms: []
        )
        #expect(prompt.contains("- Morning coffee at 07:30"))
        #expect(prompt.contains("- Dairy or calcium usually at breakfast, dinner"))
        #expect(prompt.contains("- Avoid doses during work, 09:00–17:00"))
        #expect(prompt.contains("- Avoid doses while asleep, 22:30–07:00"))
        #expect(prompt.contains("Prefers morning doses"))

        let plain = ScheduleOptimizer.preferenceLines(.standard, mealTimes: .standard)
        #expect(plain.contains("- No morning coffee"))
        #expect(plain.contains("- No dairy or calcium at meals"))
        #expect(!plain.contains { $0.contains("work") })
    }

    @Test func doseInAvoidedHoursGetsANote() {
        let entry = ScheduleSuggestion.MedicationTimes(key: "m1", times: ["13:00"], takeWithFood: false, reason: "")
        let change = ScheduleOptimizer.checkedChange(
            for: SampleData.lisinopril, entry: entry, mealTimes: .standard, preferences: busy
        )
        #expect(change.problem == nil)
        #expect(change.notes.contains { $0.contains("during your work hours") })
    }

    @Test func preferencesAreSaved() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Preference Tests \(UUID().uuidString)")
        let persistence = HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
        let store = HealthStore(persistence: persistence)
        #expect(store.schedulePreferences == .standard)
        store.schedulePreferences = busy

        #expect(HealthStore(persistence: persistence).schedulePreferences == busy)
    }
}

@MainActor
struct AbsorptionSeparationTests {
    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func violations(blocker: [TimeOfDay], affected: [TimeOfDay], before: Double, after: Double) -> Int {
        ScheduleOptimizer.separationViolations(
            blockerTimes: blocker, affectedTimes: affected, hoursBefore: before, hoursAfter: after
        ).count
    }

    @Test func dosesOutsideTheWindowPass() {
        // Cholestyramine at 08:00: other drugs 1 h before or 4 h after.
        #expect(violations(blocker: [t(8)], affected: [t(7)], before: 1, after: 4) == 0)
        #expect(violations(blocker: [t(8)], affected: [t(12)], before: 1, after: 4) == 0)
    }

    @Test func dosesInsideTheWindowFail() {
        #expect(violations(blocker: [t(8)], affected: [t(7, 30)], before: 1, after: 4) == 1)
        #expect(violations(blocker: [t(8)], affected: [t(11)], before: 1, after: 4) == 1)
        #expect(violations(blocker: [t(8)], affected: [t(8)], before: 1, after: 4) == 1)
    }

    @Test func gapsAreMeasuredAcrossMidnight() {
        // A 23:00 blocker and a 01:00 dose are only 2 hours apart.
        #expect(violations(blocker: [t(23)], affected: [t(1)], before: 1, after: 4) == 1)
        #expect(violations(blocker: [t(23)], affected: [t(3)], before: 1, after: 4) == 0)
    }

    @Test func everyBlockerDoseCounts() {
        // Fine against the 08:00 dose, but 30 minutes after the 12:30 dose.
        #expect(violations(blocker: [t(8), t(12, 30)], affected: [t(13)], before: 1, after: 4) == 1)
        #expect(violations(blocker: [t(12, 30), t(19)], affected: [t(7)], before: 4, after: 4) == 0)
    }

    @Test func sampleProposalFlagsOnlyTheVitaminD() throws {
        let proposal = SampleData.absorptionProposal
        #expect(proposal.separations.count == 3)
        #expect(proposal.hasSeparationViolations)
        let vitamin = try #require(proposal.separations.first { $0.affectedName == SampleData.vitaminD.name })
        #expect(vitamin.violations.count == 1)
        #expect(proposal.separations.filter(\.isSatisfied).count == 2)
        // The coffee side resolves to the preference time.
        #expect(proposal.separations.contains { $0.blockerName == "coffee" && $0.isSatisfied })
    }

    @Test func foodTargetsAndUncheckableSides() {
        let keyed = ScheduleOptimizer.keyed([SampleData.levothyroxine, SampleData.albuterol])
        var preferences = SchedulePreferences.standard
        preferences.dairyMeals = [.breakfast]
        let suggestion = ScheduleSuggestion(
            summary: "",
            medications: [.init(key: "m1", times: ["07:00"], takeWithFood: false, reason: "")],
            warnings: [],
            separations: [
                .init(blocker: "dairy", affected: "m1", hoursBefore: 1, hoursAfter: 4, reason: ""),
                .init(blocker: "meals", affected: "m1", hoursBefore: 0.5, hoursAfter: 2, reason: ""),
                .init(blocker: "coffee", affected: "m1", hoursBefore: 0.5, hoursAfter: 0, reason: ""),
                .init(blocker: "m2", affected: "m1", hoursBefore: 1, hoursAfter: 1, reason: ""),
                .init(blocker: "antacids", affected: "m1", hoursBefore: 4, hoursAfter: 4, reason: ""),
            ]
        )
        let proposal = ScheduleOptimizer.proposal(from: suggestion, keyed: keyed,
                                                  mealTimes: .standard, preferences: preferences)
        let checks = proposal.separations
        #expect(checks[0].isSatisfied)                  // dairy at 08:00, dose 1 h before
        #expect(checks[0].blockerName == "dairy or calcium")
        #expect(checks[1].isSatisfied)                  // meals 08:00, 12:30, 19:00
        #expect(checks[2].isSatisfied)                  // no coffee: nothing to check
        #expect(checks[3].uncheckedReason != nil)       // albuterol is as-needed
        #expect(checks[4].uncheckedReason != nil)       // not a key or food token
        #expect(!proposal.hasSeparationViolations)
    }

    @Test func responseWithSeparationsDecodes() throws {
        let answer = """
        {"summary":"","medications":[],"warnings":[],
         "separations":[{"blocker":"m1","affected":"m2","hoursBefore":1,"hoursAfter":4,"reason":"Binds it."}]}
        """
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": answer]]]
        let suggestion = try ScheduleOptimizer.decodeResponse(try JSONSerialization.data(withJSONObject: json), status: 200)
        #expect(suggestion.separations == [.init(blocker: "m1", affected: "m2", hoursBefore: 1, hoursAfter: 4, reason: "Binds it.")])
    }

    @Test func requestAsksForSeparations() throws {
        let body = ScheduleOptimizer.requestBody(prompt: "")
        let output = try #require(body["output_config"] as? [String: Any])
        let format = try #require(output["format"] as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("separations") == true)
        #expect(ScheduleOptimizer.systemPrompt.contains("cholestyramine"))
        #expect(ScheduleOptimizer.systemPrompt.contains("fat-soluble vitamins"))
        #expect(ScheduleOptimizer.systemPrompt.contains("vitamins, minerals and supplements"))
    }
}
