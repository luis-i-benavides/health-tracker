//
//  MealTimes.swift
//  health-tracker
//

import Foundation

/// When the user usually eats, wakes and goes to bed. The schedule optimizer lines up
/// with-food doses with meals and keeps doses inside waking hours.
struct MealTimes: Hashable, Codable {
    var wake: TimeOfDay
    var breakfast: TimeOfDay
    var lunch: TimeOfDay
    var dinner: TimeOfDay
    var bedtime: TimeOfDay

    static let standard = MealTimes(
        wake: TimeOfDay(hour: 7, minute: 0),
        breakfast: TimeOfDay(hour: 8, minute: 0),
        lunch: TimeOfDay(hour: 12, minute: 30),
        dinner: TimeOfDay(hour: 19, minute: 0),
        bedtime: TimeOfDay(hour: 22, minute: 30)
    )

    var meals: [(name: String, time: TimeOfDay)] {
        [("breakfast", breakfast), ("lunch", lunch), ("dinner", dinner)]
    }

    /// The meal within `toleranceMinutes` of `time`, if any.
    func meal(near time: TimeOfDay, toleranceMinutes: Int = 30) -> String? {
        meals.first { abs($0.time.id - time.id) <= toleranceMinutes }?.name
    }
}
