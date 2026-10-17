//
//  SchedulePreferences.swift
//  health-tracker
//
//  What the user wants the schedule optimizer to take into account beyond meal times:
//  coffee and dairy (which affect how some drugs are absorbed), hours to keep free of
//  doses, and whether to lean toward morning or evening doses.
//

import Foundation

enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A span of the day, which may wrap past midnight (e.g. a night shift 22:00–06:00).
struct TimeWindow: Hashable, Codable {
    var start: TimeOfDay
    var end: TimeOfDay

    func contains(_ time: TimeOfDay) -> Bool {
        start <= end
            ? time >= start && time < end
            : time >= start || time < end
    }
}

enum DoseTimePreference: String, CaseIterable, Identifiable, Codable {
    case none, morning, evening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No preference"
        case .morning: "Morning"
        case .evening: "Evening"
        }
    }
}

struct SchedulePreferences: Hashable, Codable {
    /// When the user has their morning coffee; `nil` if they don't drink it.
    var coffeeTime: TimeOfDay?
    /// Meals that usually include dairy or calcium (milk, yogurt, cheese, supplements).
    var dairyMeals: Set<Meal>
    /// Hours to keep free of doses on all days; `nil` when not set.
    var workHours: TimeWindow?
    /// Keep doses out of bedtime-to-wake-up.
    var avoidSleepHours: Bool
    var timePreference: DoseTimePreference

    static let standard = SchedulePreferences(
        coffeeTime: nil,
        dairyMeals: [],
        workHours: nil,
        avoidSleepHours: true,
        timePreference: .none
    )

    static let defaultWorkHours = TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0))
    static let defaultCoffeeTime = TimeOfDay(hour: 7, minute: 30)

    /// Why `time` falls in hours the user wants free of doses, or `nil` if it doesn't.
    func conflict(for time: TimeOfDay, mealTimes: MealTimes) -> String? {
        if let workHours, workHours.contains(time) { return "during your work hours" }
        if avoidSleepHours, TimeWindow(start: mealTimes.bedtime, end: mealTimes.wake).contains(time) {
            return "during your sleep hours"
        }
        return nil
    }
}
