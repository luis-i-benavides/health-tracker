//
//  RemindersListView.swift
//  health-tracker
//
//  Variant A — settings-style Form with toggles and editable time rows.
//

import SwiftUI

struct RemindersListView: View {
    @Environment(HealthStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    NotificationPermissionBanner()
                    if let error = store.lastSchedulingError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Medication reminders", systemImage: "pills.fill", isOn: $store.medicationRemindersEnabled)
                    if store.medicationRemindersEnabled {
                        ForEach(store.medications) { med in
                            LabeledContent(med.name) {
                                Text(med.times.map(\.displayText).formatted(.list(type: .and)))
                            }
                        }
                    }
                } header: {
                    Text("Medications")
                } footer: {
                    Text("Dose times come from your imported CSV file.")
                }

                ForEach($store.measurementReminders) { $reminder in
                    Section {
                        Toggle(isOn: $reminder.isEnabled) {
                            Label(reminder.kind.label, systemImage: reminder.kind.symbol)
                                .foregroundStyle(reminder.kind.color)
                        }
                        if reminder.isEnabled {
                            ForEach($reminder.times) { $time in
                                DatePicker("Reminder", selection: $time.asDate, displayedComponents: .hourAndMinute)
                            }
                            .onDelete { reminder.times.remove(atOffsets: $0) }

                            Button("Add Time", systemImage: "plus") {
                                let last = reminder.times.last ?? TimeOfDay(hour: 8, minute: 0)
                                reminder.times.append(TimeOfDay(hour: (last.hour + 4) % 24, minute: last.minute))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .reschedulesReminders(in: store)
        }
    }
}

#Preview("Reminders – List") {
    RemindersListView()
        .environment(HealthStore.preview)
}
