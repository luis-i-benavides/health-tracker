//
//  Medication.swift
//  health-tracker
//

import Foundation

/// A time of day (24-hour clock) at which something is scheduled.
struct TimeOfDay: Hashable, Comparable, Identifiable {
    let hour: Int
    let minute: Int

    var id: Int { hour * 60 + minute }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Parses a strict 24-hour `HH:mm` (or `H:mm`) string. Returns `nil` when invalid.
    init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// `HH:mm` representation, e.g. "08:00".
    var formatted24h: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Today's date at this time, used for display with locale-aware formatting.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.id < rhs.id
    }
}

extension Date {
    /// Default "taken at" when logging for `day`: now if `day` is today; otherwise the
    /// scheduled time on that day, or the current clock time on that day if unscheduled.
    static func defaultLogTime(on day: Date, scheduled: TimeOfDay?, calendar: Calendar = .current) -> Date {
        let now = Date.now
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let time = scheduled ?? TimeOfDay(hour: parts.hour ?? 12, minute: parts.minute ?? 0)
        return min(time.date(on: day, calendar: calendar), now)
    }
}

/// The total amount of drug in one dose, e.g. 2 tablets × 500 mg = 1,000 mg.
struct DoseAmount: Hashable {
    var value: Double
    var unit: String
}

/// A medication described the way a prescription label describes it:
/// drug name, strength, dose form and quantity, route, schedule, food rules and duration.
struct Medication: Identifiable, Hashable {
    let id: UUID
    /// As on the label; may be a brand name.
    var name: String
    /// Generic name when `name` is a brand, e.g. "metformin" for "Glucophage".
    var genericName: String?
    /// Amount of drug per unit (per tablet, per puff, per mL). `nil` when unknown.
    var strength: Strength?
    var form: DoseForm
    /// Units per dose: 1 tablet, 0.5 tablet, 2 puffs, 10 mL.
    var quantity: Double
    var route: Route
    var schedule: DoseSchedule
    var foodRules: Set<FoodRule>
    /// Fixed-length course; `nil` for ongoing medications.
    var course: Course?
    /// What it's for, e.g. "blood pressure" (shown as "for blood pressure").
    var purpose: String?
    /// When this medication was first added. Earlier days don't show its doses as missed.
    var addedOn: Date

    init(
        id: UUID = UUID(),
        name: String,
        genericName: String? = nil,
        strength: Strength?,
        form: DoseForm = .tablet,
        quantity: Double = 1,
        route: Route = .byMouth,
        schedule: DoseSchedule,
        foodRules: Set<FoodRule> = [],
        course: Course? = nil,
        purpose: String? = nil,
        addedOn: Date = .now
    ) {
        self.id = id
        self.name = name
        self.genericName = genericName
        self.strength = strength
        self.form = form
        self.quantity = quantity
        self.route = route
        self.schedule = schedule
        self.foodRules = foodRules
        self.course = course
        self.purpose = purpose
        self.addedOn = addedOn
    }

    /// Times of day a dose is due (empty for as-needed medications).
    var times: [TimeOfDay] { schedule.times }

    /// Whether doses are due on `day`: on or after `addedOn`, within the course (if any),
    /// and on one of the schedule's days. Always false for as-needed medications.
    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.startOfDay(for: addedOn) <= calendar.startOfDay(for: day) else { return false }
        if let course, !course.isActive(on: day, calendar: calendar) { return false }
        return schedule.isScheduled(on: day, calendar: calendar)
    }

    /// Total drug per dose, when it can be computed from the strength.
    /// Not computed for percentages, insulin-style "units" doses, or concentrations
    /// measured in something other than mL.
    var doseAmount: DoseAmount? {
        guard let strength, strength.isAmountPerUnit, form != .unit else { return nil }
        if let perVolume = strength.perVolume {
            guard form == .milliliter, strength.perVolumeUnit == "mL", perVolume > 0 else { return nil }
            return DoseAmount(value: quantity * strength.value / perVolume, unit: strength.unit)
        }
        return DoseAmount(value: quantity * strength.value, unit: strength.unit)
    }

    /// This medication's instructions with another's identity and start date. Used on re-import
    /// so an updated prescription stays linked to the existing medication's history.
    func adoptingIdentity(of existing: Medication) -> Medication {
        Medication(
            id: existing.id, name: name, genericName: genericName, strength: strength,
            form: form, quantity: quantity, route: route, schedule: schedule,
            foodRules: foodRules, course: course, purpose: purpose, addedOn: existing.addedOn
        )
    }

    // MARK: - Legacy bridge (CSV v1 and current screens). Screens move off these in Phase 3.

    /// Builds a medication from the original `name,dosage,unit,times` CSV format: a daily
    /// medication taken by mouth. "500 mg" becomes the strength of one tablet; a unit that's
    /// a dose form ("1 tablet", "12 units", "5 mL") becomes the quantity instead.
    init(id: UUID = UUID(), name: String, dosage: Double, unit: String, times: [TimeOfDay], addedOn: Date = .now) {
        let isStrengthUnit = Strength.normalizedUnit(unit).map { !["units", "mL"].contains($0) } ?? false
        if !isStrengthUnit, let form = DoseForm.parse(unit) {
            self.init(id: id, name: name, strength: nil, form: form, quantity: dosage,
                      schedule: .daily(times: times.sorted()), addedOn: addedOn)
        } else {
            self.init(id: id, name: name, strength: Strength(value: dosage, unit: unit),
                      schedule: .daily(times: times.sorted()), addedOn: addedOn)
        }
    }

    /// Amount per dose as a number: the drug amount when known, otherwise the unit count.
    var dosage: Double { doseAmount?.value ?? quantity }

    /// Unit for `dosage`: "mg" etc., or the dose form ("tablets").
    var unit: String {
        doseAmount?.unit ?? (quantity == 1 ? form.singular : form.plural)
    }

    /// e.g. "10 mg", "2.5 mL" or "0.075 mg". Allows up to 4 decimals so small doses are never rounded.
    var displayDosage: String {
        "\(dosage.formatted(.number.precision(.fractionLength(0...4)))) \(unit)"
    }
}
