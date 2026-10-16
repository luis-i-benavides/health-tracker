//
//  DailyRoutineSection.swift
//  health-tracker
//
//  Wake, meal and bed times, shown on the Medications tab and in Optimize Schedule.
//

import SwiftUI

struct DailyRoutineSection: View {
    @Binding var mealTimes: MealTimes

    var body: some View {
        Section {
            DatePicker("Wake up", selection: $mealTimes.wake.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Breakfast", selection: $mealTimes.breakfast.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Lunch", selection: $mealTimes.lunch.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Dinner", selection: $mealTimes.dinner.asDate, displayedComponents: .hourAndMinute)
            DatePicker("Bedtime", selection: $mealTimes.bedtime.asDate, displayedComponents: .hourAndMinute)
        } header: {
            Text("Your Day")
        } footer: {
            Text("Optimize Schedule lines up with-food doses with these meals, and new once- to four-times-daily medications start at them. Changing a time doesn't move doses that are already scheduled.")
        }
    }
}
