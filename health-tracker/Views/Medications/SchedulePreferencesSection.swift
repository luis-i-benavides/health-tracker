//
//  SchedulePreferencesSection.swift
//  health-tracker
//
//  Coffee, dairy, hours to avoid and morning/evening preference, shown on the
//  Medications tab and in Optimize Schedule.
//

import SwiftUI

struct SchedulePreferencesSection: View {
    @Binding var preferences: SchedulePreferences

    var body: some View {
        Section {
            Toggle("Morning coffee", isOn: Binding(
                get: { preferences.coffeeTime != nil },
                set: { preferences.coffeeTime = $0 ? SchedulePreferences.defaultCoffeeTime : nil }
            ))
            if preferences.coffeeTime != nil {
                DatePicker("Coffee at", selection: coffeeTime.asDate, displayedComponents: .hourAndMinute)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dairy or calcium with")
                mealPicker
            }
            .padding(.vertical, 2)

            Toggle("Avoid work hours", isOn: Binding(
                get: { preferences.workHours != nil },
                set: { preferences.workHours = $0 ? SchedulePreferences.defaultWorkHours : nil }
            ))
            if preferences.workHours != nil {
                DatePicker("Starts", selection: workHours.start.asDate, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: workHours.end.asDate, displayedComponents: .hourAndMinute)
            }
            Toggle("Avoid sleep hours", isOn: $preferences.avoidSleepHours)

            Picker("Prefer", selection: $preferences.timePreference) {
                ForEach(DoseTimePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } header: {
            Text("Schedule Preferences")
        } footer: {
            Text("Coffee, dairy and calcium can block some medications from being absorbed, so Optimize Schedule keeps those doses apart. Work hours apply every day. Sleep hours are from bedtime to wake-up. A preference gives way when a medication must be taken at a certain time.")
        }
    }

    /// Breakfast / Lunch / Dinner capsules; tap to toggle.
    private var mealPicker: some View {
        HStack {
            ForEach(Meal.allCases) { meal in
                let isOn = preferences.dairyMeals.contains(meal)
                Button(meal.label) {
                    if isOn { preferences.dairyMeals.remove(meal) } else { preferences.dairyMeals.insert(meal) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(isOn ? Color.white : Color.accentColor)
                .background(isOn ? Color.accentColor : Color.clear, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: isOn ? 0 : 1))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    // Non-optional bindings for pickers shown only while the optional value is set.

    private var coffeeTime: Binding<TimeOfDay> {
        Binding(
            get: { preferences.coffeeTime ?? SchedulePreferences.defaultCoffeeTime },
            set: { preferences.coffeeTime = $0 }
        )
    }

    private var workHours: Binding<TimeWindow> {
        Binding(
            get: { preferences.workHours ?? SchedulePreferences.defaultWorkHours },
            set: { preferences.workHours = $0 }
        )
    }
}

#Preview("Schedule Preferences") {
    @Previewable @State var preferences = SchedulePreferences(
        coffeeTime: TimeOfDay(hour: 7, minute: 30), dairyMeals: [.breakfast],
        workHours: SchedulePreferences.defaultWorkHours, avoidSleepHours: true, timePreference: .morning
    )
    Form {
        SchedulePreferencesSection(preferences: $preferences)
    }
}
