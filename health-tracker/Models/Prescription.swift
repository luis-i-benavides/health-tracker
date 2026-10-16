//
//  Prescription.swift
//  health-tracker
//
//  The building blocks of a prescription instruction ("sig"): strength, dose form, route,
//  schedule, food rules and course duration. `PrescriptionFormatter` turns these into the
//  sentence shown to the user; nothing here stores display text.
//

import Foundation

// MARK: - Strength

/// The amount of drug in one unit of the dose form, e.g. 500 mg per tablet,
/// or a concentration such as 5 mg/5 mL or 100 units/mL.
struct Strength: Hashable, Codable {
    var value: Double
    /// Normalized unit symbol, e.g. "mg", "mcg", "mL", "units", "IU", "%".
    var unit: String
    /// For concentrations: the volume the `value` is contained in (5 mL in "5 mg/5 mL").
    var perVolume: Double?
    var perVolumeUnit: String?

    init(value: Double, unit: String, perVolume: Double? = nil, perVolumeUnit: String? = nil) {
        self.value = value
        self.unit = Strength.normalizedUnit(unit) ?? unit
        self.perVolume = perVolume
        self.perVolumeUnit = perVolumeUnit.map { Strength.normalizedUnit($0) ?? $0 }
    }

    /// Parses "500 mg", "500mg", "90 mcg", "5 gr", "0.1%", "5 mg/5 mL", "100 units/mL".
    /// Returns `nil` if there's no number, no unit, or the unit isn't recognized.
    init?(parsing text: String) {
        let pattern = /^\s*(\d*\.?\d+)\s*([A-Za-zµ%]+)\s*(?:\/\s*(\d*\.?\d+)?\s*([A-Za-z]+))?\s*$/
        guard let match = text.wholeMatch(of: pattern),
              let value = Double(match.1),
              let unit = Strength.normalizedUnit(String(match.2))
        else { return nil }

        var perVolume: Double?
        var perVolumeUnit: String?
        if let volumeUnit = match.4 {
            guard let normalized = Strength.normalizedUnit(String(volumeUnit)) else { return nil }
            perVolumeUnit = normalized
            perVolume = match.3.flatMap { Double($0) } ?? 1
        }
        self.init(value: value, unit: unit, perVolume: perVolume, perVolumeUnit: perVolumeUnit)
    }

    /// Whether this strength describes mass/activity per unit (shown as "(500 mg)" after the
    /// quantity). Percentages describe a concentration, not a per-dose amount.
    var isAmountPerUnit: Bool { unit != "%" }

    /// Recognized unit spellings → normalized symbol.
    static func normalizedUnit(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "mg", "milligram", "milligrams": "mg"
        case "mcg", "µg", "ug", "microgram", "micrograms": "mcg"
        case "g", "gram", "grams": "g"
        // Apothecary grains (e.g. aspirin 5 gr, thyroid 1 gr); not to be confused with grams.
        case "gr", "grain", "grains": "gr"
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": "mL"
        case "l", "liter", "liters", "litre", "litres": "L"
        case "unit", "units": "units"
        case "iu": "IU"
        case "meq": "mEq"
        case "%", "percent": "%"
        default: nil
        }
    }
}

// MARK: - Dose form

/// What one unit of the medication is. Quantities are counted in these units ("2 puffs").
enum DoseForm: String, CaseIterable, Hashable, Codable {
    case tablet, capsule, milliliter, puff, drop, patch, application, spray, unit, suppository

    var singular: String {
        switch self {
        case .milliliter: "mL"
        default: rawValue
        }
    }

    var plural: String {
        switch self {
        case .milliliter: "mL"
        case .patch: "patches"
        default: rawValue + "s"
        }
    }

    /// Tablets can be split, so half-unit quantities make sense.
    var isSplittable: Bool { self == .tablet }

    /// CSV spellings → form.
    static func parse(_ raw: String) -> DoseForm? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "tablet", "tablets", "tab", "tabs", "pill", "pills": .tablet
        case "capsule", "capsules", "cap", "caps": .capsule
        case "ml", "milliliter", "milliliters", "liquid", "solution", "suspension", "syrup": .milliliter
        case "puff", "puffs", "inhalation", "inhalations": .puff
        case "drop", "drops", "gtt", "gtts": .drop
        case "patch", "patches": .patch
        case "application", "applications", "cream", "ointment", "gel", "lotion": .application
        case "spray", "sprays": .spray
        case "unit", "units": .unit
        case "suppository", "suppositories", "supp": .suppository
        default: nil
        }
    }
}

// MARK: - Route

/// How the drug enters the body. Determines the instruction's verb and phrasing.
enum Route: String, CaseIterable, Hashable, Codable {
    case byMouth, sublingual, inhaled, topical, transdermal, eye, ear, nasal
    case subcutaneous, intramuscular, rectal

    /// Imperative verb that starts the instruction.
    var verb: String {
        switch self {
        case .byMouth: "Take"
        case .sublingual: "Place"
        case .inhaled: "Inhale"
        case .topical, .transdermal: "Apply"
        case .eye, .ear: "Instill"
        case .nasal: "Use"
        case .subcutaneous, .intramuscular: "Inject"
        case .rectal: "Insert"
        }
    }

    /// Phrase after the quantity, e.g. "by mouth". `nil` when the verb already says it ("Inhale").
    var phrase: String? {
        switch self {
        case .byMouth: "by mouth"
        case .sublingual: "under the tongue"
        case .inhaled: nil
        case .topical: "to the affected area"
        case .transdermal: "to the skin"
        case .eye: "in the affected eye(s)"
        case .ear: "in the affected ear(s)"
        case .nasal: "in each nostril"
        case .subcutaneous: "under the skin"
        case .intramuscular: "into the muscle"
        case .rectal: "rectally"
        }
    }

    /// Short label for lists and pickers.
    var label: String {
        switch self {
        case .byMouth: "By mouth"
        case .sublingual: "Under the tongue"
        case .inhaled: "Inhaled"
        case .topical: "Topical"
        case .transdermal: "Skin patch"
        case .eye: "Eye"
        case .ear: "Ear"
        case .nasal: "Nasal"
        case .subcutaneous: "Injection (under the skin)"
        case .intramuscular: "Injection (muscle)"
        case .rectal: "Rectal"
        }
    }

    /// CSV spellings, including common pharmacy abbreviations.
    static func parse(_ raw: String) -> Route? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "by mouth", "mouth", "oral", "orally", "po": .byMouth
        case "sublingual", "sl", "under the tongue": .sublingual
        case "inhaled", "inhalation", "inh", "inhale": .inhaled
        case "topical", "topically", "skin": .topical
        case "transdermal", "td": .transdermal
        case "eye", "eyes", "ophthalmic", "ou", "os", "od": .eye
        case "ear", "ears", "otic": .ear
        case "nasal", "nose", "intranasal": .nasal
        case "subcutaneous", "subq", "sc", "sq", "injection", "inject": .subcutaneous
        case "intramuscular", "im": .intramuscular
        case "rectal", "rectally", "pr": .rectal
        default: nil
        }
    }
}

// MARK: - Food and drink rules

enum FoodRule: String, CaseIterable, Hashable, Comparable, Codable {
    case withFood, emptyStomach, fullGlassOfWater, avoidGrapefruit, avoidAlcohol

    /// Rules that read as part of the instruction sentence ("…with food").
    /// The others are separate warnings ("Avoid alcohol.").
    var isInline: Bool {
        switch self {
        case .withFood, .emptyStomach, .fullGlassOfWater: true
        case .avoidGrapefruit, .avoidAlcohol: false
        }
    }

    var phrase: String {
        switch self {
        case .withFood: "with food"
        case .emptyStomach: "on an empty stomach"
        case .fullGlassOfWater: "with a full glass of water"
        case .avoidGrapefruit: "Avoid grapefruit and grapefruit juice."
        case .avoidAlcohol: "Avoid alcohol."
        }
    }

    static func parse(_ raw: String) -> FoodRule? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "with food", "with meals", "with a meal", "food": .withFood
        case "empty stomach", "on an empty stomach": .emptyStomach
        case "full glass of water", "with a full glass of water", "with water": .fullGlassOfWater
        case "avoid grapefruit", "no grapefruit": .avoidGrapefruit
        case "avoid alcohol", "no alcohol": .avoidAlcohol
        default: nil
        }
    }

    static func < (lhs: FoodRule, rhs: FoodRule) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

// MARK: - Schedule

/// Day of the week, numbered like `Calendar.component(.weekday, …)` (Sunday = 1).
enum Weekday: Int, CaseIterable, Hashable, Comparable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var name: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// Monday-first ordering for display ("Monday, Wednesday and Friday").
    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        (lhs.rawValue + 5) % 7 < (rhs.rawValue + 5) % 7
    }

    static func parse(_ raw: String) -> Weekday? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.count >= 2 else { return nil }
        // Accept full names and unambiguous prefixes: "mon", "tues", "th", "thu", "sa"…
        let matches = allCases.filter { $0.name.lowercased().hasPrefix(text) }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum DoseSchedule: Hashable, Codable {
    /// Every day at fixed times ("twice daily" → 8 AM and 8 PM).
    case daily(times: [TimeOfDay])
    /// Around the clock at a fixed interval ("every 8 hours"). The interval divides 24.
    case everyHours(interval: Int, firstDose: TimeOfDay)
    /// Once daily at bedtime.
    case atBedtime(TimeOfDay)
    /// Selected weekdays at fixed times.
    case weekly(days: Set<Weekday>, times: [TimeOfDay])
    /// Only when needed, with a minimum gap and a maximum per rolling 24 hours.
    case asNeeded(minHoursApart: Double, maxDosesPer24h: Int)

    /// The times of day a dose is due on a day it's scheduled (empty for as-needed).
    var times: [TimeOfDay] {
        switch self {
        case .daily(let times), .weekly(_, let times):
            return times.sorted()
        case .atBedtime(let time):
            return [time]
        case .everyHours(let interval, let first):
            let count = 24 / interval
            return (0..<count)
                .map { (first.hour * 60 + first.minute + $0 * interval * 60) % (24 * 60) }
                .map { TimeOfDay(hour: $0 / 60, minute: $0 % 60) }
                .sorted()
        case .asNeeded:
            return []
        }
    }

    var isAsNeeded: Bool {
        if case .asNeeded = self { true } else { false }
    }

    /// Whether doses are scheduled on the given day (ignores the medication's course).
    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .asNeeded:
            return false
        case .weekly(let days, _):
            return Weekday(rawValue: calendar.component(.weekday, from: day)).map(days.contains) ?? false
        default:
            return true
        }
    }
}

// MARK: - Course

/// A fixed-length course, e.g. 10 days of an antibiotic. Medications without one are ongoing.
struct Course: Hashable, Codable {
    /// Start of the first day of the course.
    var startDate: Date
    var days: Int

    init(startDate: Date, days: Int, calendar: Calendar = .current) {
        self.startDate = calendar.startOfDay(for: startDate)
        self.days = days
    }

    /// Start of the last day of the course.
    func lastDay(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
    }

    /// 1-based day of the course, or `nil` if `date` is outside it.
    func dayNumber(on date: Date, calendar: Calendar = .current) -> Int? {
        let day = calendar.startOfDay(for: date)
        guard let offset = calendar.dateComponents([.day], from: startDate, to: day).day,
              (0..<days).contains(offset)
        else { return nil }
        return offset + 1
    }

    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        dayNumber(on: date, calendar: calendar) != nil
    }
}
