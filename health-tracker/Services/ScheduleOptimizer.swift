//
//  ScheduleOptimizer.swift
//  health-tracker
//
//  Asks Claude to choose dose times: as few times a day as possible, with-food doses at
//  meals, and nausea-prone medications protected by food and (when the user has one) an
//  anti-nausea medication taken beforehand. Only the times change — never the drug, dose,
//  number of doses a day, interval or weekdays — and the app checks every suggestion
//  before showing it. Nothing is applied until the user approves.
//
//  Swift has no official Anthropic SDK, so this calls the Messages API over HTTP.
//

import Foundation

// MARK: - What Claude returns

/// The structured response (see `ScheduleOptimizer.responseSchema`).
struct ScheduleSuggestion: Decodable, Equatable {
    struct MedicationTimes: Decodable, Equatable {
        /// The short key the medication was sent with ("m1", "m2"…).
        let key: String
        /// 24-hour "HH:mm" times.
        let times: [String]
        /// Take with food even though the prescription doesn't say so (e.g. it often causes nausea).
        let takeWithFood: Bool
        let reason: String
    }

    struct Warning: Decodable, Equatable {
        enum Severity: String, Decodable { case info, caution, important }
        let severity: Severity
        let message: String
        let medicationKeys: [String]
    }

    let summary: String
    let medications: [MedicationTimes]
    let warnings: [Warning]
}

// MARK: - Checked proposal shown to the user

/// One medication's suggested change, after checking it against the prescription.
struct ProposedScheduleChange: Identifiable, Hashable {
    let medication: Medication
    /// The suggested schedule, same kind as the current one. Equal to the current schedule
    /// when the suggestion was rejected (`problem` explains why) or nothing changed.
    let schedule: DoseSchedule
    let addsWithFood: Bool
    let reason: String
    /// Why the suggestion couldn't be used; the current times are kept.
    let problem: String?
    /// Soft concerns the app noticed, e.g. a with-food dose that isn't at a meal.
    let notes: [String]

    var id: Medication.ID { medication.id }
    var oldTimes: [TimeOfDay] { medication.times }
    var newTimes: [TimeOfDay] { schedule.times }
    var changesSomething: Bool { problem == nil && (schedule != medication.schedule || addsWithFood) }
}

struct ScheduleProposal: Hashable {
    let summary: String
    let changes: [ProposedScheduleChange]
    let warnings: [ProposalWarning]
    /// Distinct clock times with a scheduled dose, before and after.
    let distinctTimesBefore: Int
    let distinctTimesAfter: Int

    var hasChanges: Bool { changes.contains(where: \.changesSomething) }
}

struct ProposalWarning: Hashable, Identifiable {
    let severity: ScheduleSuggestion.Warning.Severity
    let message: String
    let medicationNames: [String]

    var id: String { message }
}

// MARK: - Errors

enum ScheduleOptimizerError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case overloaded
    case refused
    case truncated
    case malformedResponse
    case server(status: Int, message: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Anthropic API key to optimize the schedule."
        case .invalidAPIKey: "The Anthropic API key was rejected. Check it and try again."
        case .rateLimited: "Too many requests right now. Wait a minute and try again."
        case .overloaded: "Claude is busy right now. Try again in a few minutes."
        case .refused: "Claude declined to make suggestions for this medication list."
        case .truncated: "The suggestion was cut off before it finished. Try again."
        case .malformedResponse: "The suggestion couldn't be read. Try again."
        case .server(let status, let message): "The request failed (\(status)): \(message)"
        case .network(let message): "Couldn't reach Claude: \(message)"
        }
    }
}

// MARK: - Optimizer

struct ScheduleOptimizer {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String
    var session: URLSession = .shared

    /// Asks Claude for new times and returns the checked proposal.
    func propose(
        medications: [Medication],
        mealTimes: MealTimes,
        recentSymptoms: [SymptomLog],
        today: Date = .now
    ) async throws -> ScheduleProposal {
        guard !apiKey.isEmpty else { throw ScheduleOptimizerError.missingAPIKey }
        let included = Self.medicationsToSchedule(medications, today: today)
        let keyed = Self.keyed(included)
        let body = Self.requestBody(
            prompt: Self.prompt(keyed: keyed, mealTimes: mealTimes, symptoms: recentSymptoms)
        )

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Lets the API retry on another model if the request is declined by a safety classifier.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ScheduleOptimizerError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let suggestion = try Self.decodeResponse(data, status: status)
        return Self.proposal(from: suggestion, keyed: keyed, mealTimes: mealTimes)
    }

    // MARK: Which medications

    /// Scheduled medications that are current: as-needed ones have no times, and finished
    /// courses no longer matter. As-needed medications are still described to Claude.
    static func medicationsToSchedule(_ medications: [Medication], today: Date, calendar: Calendar = .current) -> [Medication] {
        medications.filter { medication in
            guard let course = medication.course else { return true }
            return course.lastDay(calendar: calendar) >= calendar.startOfDay(for: today)
        }
    }

    /// Short keys keep the prompt compact and are easy for the model to echo exactly.
    static func keyed(_ medications: [Medication]) -> [(key: String, medication: Medication)] {
        medications.enumerated().map { ("m\($0.offset + 1)", $0.element) }
    }

    // MARK: Request

    static let systemPrompt = """
    You are a clinical pharmacist helping a patient arrange the times of day they take \
    their medications. Use your knowledge of each drug — absorption, food effects, common \
    side effects such as nausea, and interactions between drugs on the list.

    Goals, in priority order:
    1. Safety: keep doses that interact apart when timing helps (for example, separate \
    drugs whose absorption is blocked by calcium, iron or antacids), keep required spacing \
    between doses of the same drug, and respect "empty stomach" instructions.
    2. Food: put doses that must be taken with food at a meal. Drugs that commonly cause \
    nausea or stomach upset should be taken with food even when the label doesn't say so — \
    set takeWithFood for those. If the patient has an anti-nausea medication on a fixed \
    schedule, time it 30–60 minutes before the nausea-causing doses where its pharmacology \
    supports that. If their anti-nausea medication is as-needed only, or they have none, \
    say so in a warning instead of inventing a dose.
    3. Fewer times: use as few distinct clock times per day as possible, grouping doses \
    at meals and bedtime.
    4. Convenience: keep doses between waking and bedtime unless a schedule requires otherwise.

    Rules you must follow:
    - Only change times. Never change a drug, dose, how many doses a day, the interval of \
    an "every N hours" schedule, or the weekdays of a weekly schedule.
    - Return one entry for every medication listed under "Scheduled", using its key, with \
    exactly the same number of times. "Every N hours" times must stay exactly N hours apart. \
    Times are 24-hour HH:mm.
    - Don't return entries for as-needed medications; mention them in warnings if relevant.
    - Use warnings for interactions, duplicate therapy, or anything the patient should \
    raise with their pharmacist or prescriber. Keep each reason and warning to one or two \
    plain-language sentences.
    """

    static func prompt(keyed: [(key: String, medication: Medication)], mealTimes: MealTimes, symptoms: [SymptomLog]) -> String {
        let formatter = PrescriptionFormatter()
        let scheduled = keyed.filter { !$0.medication.schedule.isAsNeeded }
        let asNeeded = keyed.filter { $0.medication.schedule.isAsNeeded }

        func describe(_ entry: (key: String, medication: Medication)) -> String {
            let med = entry.medication
            var lines = ["- key: \(entry.key)", "  name: \(med.name)"]
            if let generic = med.genericName { lines.append("  generic: \(generic)") }
            if let strength = med.strength { lines.append("  strength: \(formatter.strengthText(strength))") }
            lines.append("  dose: \(formatter.doseText(for: med)), \(med.route.label.lowercased())")
            lines.append("  schedule: \(scheduleConstraint(med.schedule))")
            if !med.foodRules.isEmpty {
                let rules = med.foodRules.sorted().map { $0.phrase.trimmingCharacters(in: .punctuationCharacters) }
                lines.append("  food and drink: \(rules.joined(separator: "; "))")
            }
            if let purpose = med.purpose { lines.append("  for: \(purpose)") }
            if let course = med.course { lines.append("  course: \(course.days) days") }
            return lines.joined(separator: "\n")
        }

        var text = """
        Daily routine: wakes \(mealTimes.wake.formatted24h), breakfast \(mealTimes.breakfast.formatted24h), \
        lunch \(mealTimes.lunch.formatted24h), dinner \(mealTimes.dinner.formatted24h), \
        bedtime \(mealTimes.bedtime.formatted24h).

        Scheduled:
        \(scheduled.isEmpty ? "(none)" : scheduled.map(describe).joined(separator: "\n"))

        As needed (not scheduled):
        \(asNeeded.isEmpty ? "(none)" : asNeeded.map(describe).joined(separator: "\n"))
        """

        let summary = symptomSummary(symptoms)
        if !summary.isEmpty {
            text += "\n\nSymptoms logged in the last 14 days:\n" + summary
        }
        return text
    }

    /// What may change for each kind of schedule.
    static func scheduleConstraint(_ schedule: DoseSchedule) -> String {
        switch schedule {
        case .daily(let times):
            "\(times.count)× daily, currently \(timeList(times)) — choose \(times.count) time(s)"
        case .everyHours(let interval, _):
            "every \(interval) hours, currently \(timeList(schedule.times)) — choose \(24 / interval) times exactly \(interval) hours apart"
        case .atBedtime(let time):
            "once daily at bedtime, currently \(time.formatted24h) — choose 1 time"
        case .weekly(let days, let times):
            "on \(days.sorted().map(\.name).joined(separator: ", ")) only, currently \(timeList(times)) — choose \(times.count) time(s); days stay the same"
        case .asNeeded(let minHours, let maxDoses):
            "as needed, at least \(minHours.formatted()) hours apart, at most \(maxDoses) doses in 24 hours"
        }
    }

    private static func timeList(_ times: [TimeOfDay]) -> String {
        times.sorted().map(\.formatted24h).joined(separator: ", ")
    }

    /// e.g. "- Nausea: 3 times (moderate), at 08:40, 09:10, 13:05".
    static func symptomSummary(_ symptoms: [SymptomLog], calendar: Calendar = .current) -> String {
        Dictionary(grouping: symptoms, by: \.displayName)
            .sorted { $0.value.count > $1.value.count }
            .map { name, logs in
                let worst = logs.map(\.severity).max()?.label.lowercased() ?? ""
                let times = logs.sorted { $0.date < $1.date }.suffix(10).map { log in
                    let parts = calendar.dateComponents([.hour, .minute], from: log.date)
                    return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0).formatted24h
                }
                return "- \(name): \(logs.count) time(s) (worst: \(worst)), at \(times.joined(separator: ", "))"
            }
            .joined(separator: "\n")
    }

    static let responseSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "medications", "warnings"],
        "properties": [
            "summary": [
                "type": "string",
                "description": "Two or three sentences describing the new daily routine.",
            ],
            "medications": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["key", "times", "takeWithFood", "reason"],
                    "properties": [
                        "key": ["type": "string"],
                        "times": ["type": "array", "items": ["type": "string", "description": "24-hour HH:mm"]],
                        "takeWithFood": ["type": "boolean"],
                        "reason": ["type": "string"],
                    ],
                ],
            ],
            "warnings": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["severity", "message", "medicationKeys"],
                    "properties": [
                        "severity": ["type": "string", "enum": ["info", "caution", "important"]],
                        "message": ["type": "string"],
                        "medicationKeys": ["type": "array", "items": ["type": "string"]],
                    ],
                ],
            ],
        ],
    ]

    static func requestBody(prompt: String) -> [String: Any] {
        [
            "model": model,
            // Non-streaming; plenty of room for thinking plus the JSON answer.
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                // Drug knowledge and trade-offs benefit from deeper reasoning.
                "effort": "high",
                "format": ["type": "json_schema", "schema": responseSchema],
            ],
            "fallbacks": "default",
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]],
        ]
    }

    // MARK: Response

    static func decodeResponse(_ data: Data, status: Int) throws -> ScheduleSuggestion {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "Unknown error"
            switch status {
            case 401, 403: throw ScheduleOptimizerError.invalidAPIKey
            case 429: throw ScheduleOptimizerError.rateLimited
            case 529: throw ScheduleOptimizerError.overloaded
            default: throw ScheduleOptimizerError.server(status: status, message: message)
            }
        }
        guard let json else { throw ScheduleOptimizerError.malformedResponse }

        // Check why generation stopped before reading the content.
        switch json["stop_reason"] as? String {
        case "refusal": throw ScheduleOptimizerError.refused
        case "max_tokens": throw ScheduleOptimizerError.truncated
        default: break
        }

        // The answer is the text block(s); thinking and fallback blocks are skipped.
        let text = ((json["content"] as? [[String: Any]]) ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let answer = text.data(using: .utf8),
              let suggestion = try? JSONDecoder().decode(ScheduleSuggestion.self, from: answer)
        else { throw ScheduleOptimizerError.malformedResponse }
        return suggestion
    }

    // MARK: Checking the suggestion

    /// Turns Claude's suggestion into a proposal, rejecting anything that would change more
    /// than the times. Rejected medications keep their current schedule.
    static func proposal(
        from suggestion: ScheduleSuggestion,
        keyed: [(key: String, medication: Medication)],
        mealTimes: MealTimes
    ) -> ScheduleProposal {
        let byKey = Dictionary(suggestion.medications.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let scheduled = keyed.filter { !$0.medication.schedule.isAsNeeded }

        let changes = scheduled.map { key, medication in
            guard let entry = byKey[key] else {
                return ProposedScheduleChange(
                    medication: medication, schedule: medication.schedule, addsWithFood: false,
                    reason: "", problem: "No suggestion was returned, so the current times are kept.", notes: []
                )
            }
            return checkedChange(for: medication, entry: entry, mealTimes: mealTimes)
        }

        let names = Dictionary(keyed.map { ($0.key, $0.medication.name) }, uniquingKeysWith: { first, _ in first })
        let warnings = suggestion.warnings.map {
            ProposalWarning(severity: $0.severity, message: $0.message,
                            medicationNames: $0.medicationKeys.compactMap { names[$0] })
        }

        func distinctTimes(_ schedules: [DoseSchedule]) -> Int {
            Set(schedules.flatMap(\.times)).count
        }
        return ScheduleProposal(
            summary: suggestion.summary,
            changes: changes,
            warnings: warnings,
            distinctTimesBefore: distinctTimes(changes.map(\.medication.schedule)),
            distinctTimesAfter: distinctTimes(changes.map(\.schedule))
        )
    }

    static func checkedChange(
        for medication: Medication,
        entry: ScheduleSuggestion.MedicationTimes,
        mealTimes: MealTimes
    ) -> ProposedScheduleChange {
        func rejected(_ problem: String) -> ProposedScheduleChange {
            ProposedScheduleChange(medication: medication, schedule: medication.schedule, addsWithFood: false,
                                   reason: entry.reason, problem: problem, notes: [])
        }

        let parsed = entry.times.map { TimeOfDay(string: $0) }
        guard !parsed.contains(nil) else { return rejected("A suggested time wasn't valid, so the current times are kept.") }
        let times = parsed.compactMap { $0 }.sorted()
        guard Set(times).count == times.count else { return rejected("The suggestion repeated a time, so the current times are kept.") }
        guard times.count == medication.times.count else {
            return rejected("The suggestion changed the number of doses a day, so the current times are kept.")
        }

        let schedule: DoseSchedule
        switch medication.schedule {
        case .daily:
            schedule = .daily(times: times)
        case .weekly(let days, _):
            schedule = .weekly(days: days, times: times)
        case .atBedtime:
            schedule = .atBedtime(times[0])
        case .everyHours(let interval, _):
            // Each gap (wrapping past midnight) must equal the interval.
            let minutes = times.map(\.id)
            let gaps = zip(minutes, minutes.dropFirst() + [minutes[0] + 24 * 60]).map { $1 - $0 }
            guard gaps.allSatisfy({ $0 == interval * 60 }) else {
                return rejected("The suggested times weren't \(interval) hours apart, so the current times are kept.")
            }
            schedule = .everyHours(interval: interval, firstDose: times[0])
        case .asNeeded:
            return rejected("As-needed medications have no scheduled times.")
        }

        // Food advice can't contradict an empty-stomach instruction.
        let addsWithFood = entry.takeWithFood
            && !medication.foodRules.contains(.withFood)
            && !medication.foodRules.contains(.emptyStomach)

        var notes: [String] = []
        if medication.foodRules.contains(.withFood) || addsWithFood {
            let offMeal = times.filter { mealTimes.meal(near: $0) == nil }
            if !offMeal.isEmpty {
                let list = offMeal.map(\.displayText).joined(separator: ", ")
                notes.append("Taken with food, but \(list) isn't at one of your meal times — have a snack with it.")
            }
        }
        if medication.foodRules.contains(.emptyStomach), times.contains(where: { mealTimes.meal(near: $0) != nil }) {
            notes.append("Should be taken on an empty stomach, but a suggested time is close to a meal.")
        }

        return ProposedScheduleChange(medication: medication, schedule: schedule, addsWithFood: addsWithFood,
                                      reason: entry.reason, problem: nil, notes: notes)
    }
}

// MARK: - Applying

extension HealthStore {
    /// Applies the accepted changes and reschedules reminders.
    func apply(_ proposal: ScheduleProposal) async {
        applyChanges(of: proposal)
        await rescheduleNotifications()
    }

    /// Updates each changed medication's schedule and food rules.
    func applyChanges(of proposal: ScheduleProposal) {
        for change in proposal.changes where change.changesSomething {
            guard var medication = medication(for: change.medication.id) else { continue }
            medication.schedule = change.schedule
            if change.addsWithFood { medication.foodRules.insert(.withFood) }
            updateMedication(medication)
        }
    }
}
