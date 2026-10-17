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

    /// "Keep A and B apart": B must be taken at least `hoursBefore` hours before A, or at
    /// least `hoursAfter` hours after it. Either side is a medication key or a food token
    /// (`SeparationTarget`).
    struct Separation: Decodable, Equatable {
        /// What reduces absorption, e.g. a bile acid sequestrant.
        let blocker: String
        /// What it reduces the absorption of.
        let affected: String
        let hoursBefore: Double
        let hoursAfter: Double
        let reason: String
    }

    let summary: String
    let medications: [MedicationTimes]
    let warnings: [Warning]
    var separations: [Separation] = []
}

extension ScheduleSuggestion {
    private enum CodingKeys: String, CodingKey {
        case summary, medications, warnings, separations
    }

    /// Decodes in an extension so the memberwise initializer stays available. A missing
    /// `separations` list (the schema requires it) decodes as empty rather than failing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        medications = try container.decode([MedicationTimes].self, forKey: .medications)
        warnings = try container.decode([Warning].self, forKey: .warnings)
        separations = try container.decodeIfPresent([Separation].self, forKey: .separations) ?? []
    }
}

/// The food-side targets a separation can name, mapped to the user's routine.
enum SeparationTarget: String, CaseIterable {
    /// Every meal (e.g. dietary fat, or "take on an empty stomach").
    case meals
    /// The meals the user marked as having dairy or calcium.
    case dairy
    /// Morning coffee.
    case coffee
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
    let separations: [ProposalSeparation]
    /// Distinct clock times with a scheduled dose, before and after.
    let distinctTimesBefore: Int
    let distinctTimesAfter: Int

    var hasChanges: Bool { changes.contains(where: \.changesSomething) }
    var hasSeparationViolations: Bool { separations.contains { !$0.isSatisfied } }
}

/// A separation Claude said it applied, checked against the proposed times.
struct ProposalSeparation: Hashable, Identifiable {
    let blockerName: String
    let affectedName: String
    let hoursBefore: Double
    let hoursAfter: Double
    let reason: String
    /// Dose pairs closer than the separation allows; empty when it holds.
    let violations: [String]
    /// Set when the times couldn't be checked (e.g. an as-needed medication).
    let uncheckedReason: String?

    var id: String { "\(blockerName)|\(affectedName)" }
    var isSatisfied: Bool { violations.isEmpty }
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
        preferences: SchedulePreferences,
        recentSymptoms: [SymptomLog],
        today: Date = .now
    ) async throws -> ScheduleProposal {
        guard !apiKey.isEmpty else { throw ScheduleOptimizerError.missingAPIKey }
        let included = Self.medicationsToSchedule(medications, today: today)
        let keyed = Self.keyed(included)
        let body = Self.requestBody(
            prompt: Self.prompt(keyed: keyed, mealTimes: mealTimes, preferences: preferences, symptoms: recentSymptoms)
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
        return Self.proposal(from: suggestion, keyed: keyed, mealTimes: mealTimes, preferences: preferences)
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
    1. Safety: keep doses that interact apart when timing helps, keep required spacing \
    between doses of the same drug, and respect "empty stomach" instructions. See \
    "Absorption" below.
    2. Food: put doses that must be taken with food at a meal. Drugs that commonly cause \
    nausea or stomach upset should be taken with food even when the label doesn't say so — \
    set takeWithFood for those. If the patient has an anti-nausea medication on a fixed \
    schedule, time it 30–60 minutes before the nausea-causing doses where its pharmacology \
    supports that. If their anti-nausea medication is as-needed only, or they have none, \
    say so in a warning instead of inventing a dose.
    3. Fewer times: use as few distinct clock times per day as possible, grouping doses \
    at meals and bedtime.
    4. Preferences: keep doses out of the hours the patient wants free (work, sleep), and \
    lean toward their preferred time of day when a drug can go either way. Use their coffee \
    and dairy habits: keep drugs whose absorption coffee, calcium or dairy reduces (for \
    example levothyroxine, iron, some antibiotics, bisphosphonates) far enough from them. \
    If a safety or food rule forces a dose into an avoided hour, do it and explain why in \
    a warning.

    Absorption:
    Check every pair on the list — prescription drugs, over-the-counter drugs, vitamins, \
    minerals and supplements alike — for one reducing the absorption of another, and check \
    each drug against food. Examples, not a complete list:
    - Bile acid sequestrants (cholestyramine, colestipol, colesevelam) bind other drugs and \
    fat-soluble vitamins (A, D, E, K); other drugs usually go at least 1 hour before or \
    4–6 hours after them.
    - Calcium, iron, magnesium, zinc, antacids and sucralfate reduce absorption of \
    levothyroxine, tetracyclines, fluoroquinolones, bisphosphonates and others.
    - Orlistat reduces absorption of fat-soluble vitamins.
    - Levothyroxine and bisphosphonates need an empty stomach, away from food, coffee and \
    calcium.
    For every interaction that timing can manage, add an entry to "separations" and choose \
    times that satisfy it. "blocker" and "affected" are each a medication key, or one of \
    "meals" (all meals), "dairy" (the patient's dairy or calcium meals) or "coffee". \
    "affected" must be taken at least hoursBefore hours before "blocker", or at least \
    hoursAfter hours after it. If a needed vitamin isn't on the list (for example, \
    fat-soluble vitamins with long-term cholestyramine), say so in a warning. If the \
    separations can't all be met within waking hours, choose the safest arrangement and add \
    an "important" warning explaining which one isn't met.

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

    static func prompt(
        keyed: [(key: String, medication: Medication)],
        mealTimes: MealTimes,
        preferences: SchedulePreferences,
        symptoms: [SymptomLog]
    ) -> String {
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

        Preferences:
        \(preferenceLines(preferences, mealTimes: mealTimes).joined(separator: "\n"))

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

    /// One line per preference, e.g. "- Morning coffee at 07:30".
    static func preferenceLines(_ preferences: SchedulePreferences, mealTimes: MealTimes) -> [String] {
        var lines: [String] = []
        lines.append(preferences.coffeeTime.map { "- Morning coffee at \($0.formatted24h)" } ?? "- No morning coffee")
        let dairy = Meal.allCases.filter(preferences.dairyMeals.contains).map(\.rawValue)
        lines.append(dairy.isEmpty
            ? "- No dairy or calcium at meals"
            : "- Dairy or calcium usually at \(dairy.joined(separator: ", "))")
        if let work = preferences.workHours {
            lines.append("- Avoid doses during work, \(work.start.formatted24h)–\(work.end.formatted24h)")
        }
        if preferences.avoidSleepHours {
            lines.append("- Avoid doses while asleep, \(mealTimes.bedtime.formatted24h)–\(mealTimes.wake.formatted24h)")
        }
        switch preferences.timePreference {
        case .none: break
        case .morning: lines.append("- Prefers morning doses when a drug can be taken either morning or evening")
        case .evening: lines.append("- Prefers evening doses when a drug can be taken either morning or evening")
        }
        return lines
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
        "required": ["summary", "medications", "warnings", "separations"],
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
            "separations": [
                "type": "array",
                "description": "Absorption interactions handled by timing.",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["blocker", "affected", "hoursBefore", "hoursAfter", "reason"],
                    "properties": [
                        "blocker": ["type": "string", "description": "Medication key, or meals, dairy or coffee."],
                        "affected": ["type": "string", "description": "Medication key, or meals, dairy or coffee."],
                        "hoursBefore": ["type": "number"],
                        "hoursAfter": ["type": "number"],
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
        mealTimes: MealTimes,
        preferences: SchedulePreferences
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
            return checkedChange(for: medication, entry: entry, mealTimes: mealTimes, preferences: preferences)
        }

        let names = Dictionary(keyed.map { ($0.key, $0.medication.name) }, uniquingKeysWith: { first, _ in first })
        let warnings = suggestion.warnings.map {
            ProposalWarning(severity: $0.severity, message: $0.message,
                            medicationNames: $0.medicationKeys.compactMap { names[$0] })
        }

        // Check each separation against the schedule as it would be after applying.
        let medicationsByKey = Dictionary(keyed.map { ($0.key, $0.medication) }, uniquingKeysWith: { first, _ in first })
        let finalTimes = Dictionary(changes.map { ($0.medication.id, $0.newTimes) }, uniquingKeysWith: { first, _ in first })
        let separations = suggestion.separations.map {
            checkedSeparation($0, medications: medicationsByKey, finalTimes: finalTimes,
                              mealTimes: mealTimes, preferences: preferences)
        }

        func distinctTimes(_ schedules: [DoseSchedule]) -> Int {
            Set(schedules.flatMap(\.times)).count
        }
        return ScheduleProposal(
            summary: suggestion.summary,
            changes: changes,
            warnings: warnings,
            separations: separations,
            distinctTimesBefore: distinctTimes(changes.map(\.medication.schedule)),
            distinctTimesAfter: distinctTimes(changes.map(\.schedule))
        )
    }

    static func checkedChange(
        for medication: Medication,
        entry: ScheduleSuggestion.MedicationTimes,
        mealTimes: MealTimes,
        preferences: SchedulePreferences
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
        for time in times {
            if let conflict = preferences.conflict(for: time, mealTimes: mealTimes) {
                notes.append("\(time.displayText) is \(conflict).")
            }
        }

        return ProposedScheduleChange(medication: medication, schedule: schedule, addsWithFood: addsWithFood,
                                      reason: entry.reason, problem: nil, notes: notes)
    }
}

// MARK: - Separations

extension ScheduleOptimizer {
    /// What one side of a separation refers to, resolved against the user's data.
    struct ResolvedTarget {
        let name: String
        /// Times of day it happens; empty when there's nothing to check (e.g. no coffee).
        let times: [TimeOfDay]
        /// Why it can't be checked, e.g. an as-needed medication with no fixed times.
        let uncheckable: String?
    }

    static func resolve(
        _ reference: String,
        medications: [String: Medication],
        finalTimes: [Medication.ID: [TimeOfDay]],
        mealTimes: MealTimes,
        preferences: SchedulePreferences
    ) -> ResolvedTarget? {
        if let medication = medications[reference] {
            if medication.schedule.isAsNeeded {
                return ResolvedTarget(name: medication.name, times: [],
                                      uncheckable: "\(medication.name) is taken as needed, so keep this gap when you take it.")
            }
            return ResolvedTarget(name: medication.name, times: finalTimes[medication.id] ?? medication.times, uncheckable: nil)
        }
        switch SeparationTarget(rawValue: reference.lowercased()) {
        case .meals:
            return ResolvedTarget(name: "meals", times: mealTimes.meals.map(\.time), uncheckable: nil)
        case .dairy:
            let times = Meal.allCases.filter(preferences.dairyMeals.contains).map { meal in
                switch meal {
                case .breakfast: mealTimes.breakfast
                case .lunch: mealTimes.lunch
                case .dinner: mealTimes.dinner
                }
            }
            return ResolvedTarget(name: "dairy or calcium", times: times, uncheckable: nil)
        case .coffee:
            return ResolvedTarget(name: "coffee", times: preferences.coffeeTime.map { [$0] } ?? [], uncheckable: nil)
        case nil:
            return nil
        }
    }

    static func checkedSeparation(
        _ separation: ScheduleSuggestion.Separation,
        medications: [String: Medication],
        finalTimes: [Medication.ID: [TimeOfDay]],
        mealTimes: MealTimes,
        preferences: SchedulePreferences
    ) -> ProposalSeparation {
        let blocker = resolve(separation.blocker, medications: medications, finalTimes: finalTimes,
                              mealTimes: mealTimes, preferences: preferences)
        let affected = resolve(separation.affected, medications: medications, finalTimes: finalTimes,
                               mealTimes: mealTimes, preferences: preferences)

        func result(violations: [String] = [], unchecked: String? = nil) -> ProposalSeparation {
            ProposalSeparation(
                blockerName: blocker?.name ?? separation.blocker,
                affectedName: affected?.name ?? separation.affected,
                hoursBefore: separation.hoursBefore, hoursAfter: separation.hoursAfter,
                reason: separation.reason, violations: violations, uncheckedReason: unchecked
            )
        }

        guard let blocker, let affected else {
            return result(unchecked: "The app couldn't tell what this refers to, so it wasn't checked.")
        }
        if let reason = blocker.uncheckable ?? affected.uncheckable {
            return result(unchecked: reason)
        }
        let violations = separationViolations(
            blockerTimes: blocker.times, affectedTimes: affected.times,
            hoursBefore: separation.hoursBefore, hoursAfter: separation.hoursAfter
        ).map { blockerTime, affectedTime in
            "\(affected.name.sentenceCased) at \(affectedTime.displayText) is too close to \(blocker.name) at \(blockerTime.displayText)."
        }
        return result(violations: violations)
    }

    /// Pairs (blocker time, affected time) closer than allowed: the affected dose must stay
    /// out of the window from `hoursBefore` before each blocker dose to `hoursAfter` after it.
    /// Measured around the clock, since both repeat daily (23:00 and 01:00 are 2 hours apart).
    static func separationViolations(
        blockerTimes: [TimeOfDay],
        affectedTimes: [TimeOfDay],
        hoursBefore: Double,
        hoursAfter: Double
    ) -> [(TimeOfDay, TimeOfDay)] {
        let day = 24 * 60
        let before = Int((hoursBefore * 60).rounded())
        let after = Int((hoursAfter * 60).rounded())
        var violations: [(TimeOfDay, TimeOfDay)] = []
        for blocker in blockerTimes {
            for affected in affectedTimes {
                // Minutes from this blocker dose to the affected dose, and from the affected
                // dose to the next blocker dose.
                let sinceBlocker = ((affected.id - blocker.id) % day + day) % day
                let untilBlocker = sinceBlocker == 0 ? 0 : day - sinceBlocker
                if sinceBlocker < after || untilBlocker < before {
                    violations.append((blocker, affected))
                }
            }
        }
        return violations
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
