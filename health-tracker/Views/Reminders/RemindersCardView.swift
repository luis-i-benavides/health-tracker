//
//  RemindersCardView.swift
//  health-tracker
//
//  Variant B — one card per measurement type with time chips, plus a medications card.
//

import SwiftUI

struct RemindersCardView: View {
    @Environment(HealthStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NotificationPermissionBanner()
                        .cardStyle()

                    medicationsCard

                    Text("Measurements")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach($store.measurementReminders) { $reminder in
                            measurementCard($reminder)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reminders")
            .reschedulesReminders(in: store)
        }
    }

    private var medicationsCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.medicationRemindersEnabled) {
                Label("Medication doses", systemImage: "pills.fill")
                    .font(.headline)
            }
            let count = store.medications.reduce(0) { $0 + $1.times.count }
            Text("\(count) daily reminders across \(store.medications.count) medications")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func measurementCard(_ reminder: Binding<MeasurementReminder>) -> some View {
        let kind = reminder.wrappedValue.kind
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(kind.color, in: .rect(cornerRadius: 12))
                Text(kind.label)
                    .font(.headline)
                Spacer()
                Toggle(kind.label, isOn: reminder.isEnabled)
                    .labelsHidden()
            }

            if reminder.wrappedValue.isEnabled {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(reminder.times) { $time in
                            DatePicker("Time", selection: $time.asDate, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .contextMenu {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        reminder.wrappedValue.times.removeAll { $0 == time }
                                    }
                                }
                        }
                        Button("Add time", systemImage: "plus") {
                            let last = reminder.wrappedValue.times.last ?? TimeOfDay(hour: 8, minute: 0)
                            reminder.wrappedValue.times.append(TimeOfDay(hour: (last.hour + 4) % 24, minute: last.minute))
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .cardStyle()
        .opacity(reminder.wrappedValue.isEnabled ? 1 : 0.6)
    }
}

#Preview("Reminders – Cards") {
    RemindersCardView()
        .environment(HealthStore.preview)
}
