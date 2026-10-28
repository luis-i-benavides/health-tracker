//
//  RemindersCardView.swift
//  health-tracker
//
//  One card per measurement type with time chips, plus a medications card.
//

import SwiftUI

struct RemindersCardView: View {
    @Environment(HealthStore.self) private var store

    /// Measurement being recorded on demand from a card.
    @State private var measurementToRecord: MeasurementKind?

    private let formatter = PrescriptionFormatter()

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NotificationPermissionBanner()
                        .cardStyle()

                    medicationsCard

                    AlarmsCardView()

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
            .sheet(item: $measurementToRecord) { kind in
                LogMeasurementView(kind: kind)
            }
        }
    }

    private var medicationsCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.medicationRemindersEnabled) {
                Label("Medication doses", systemImage: "pills.fill")
                    .font(.headline)
            }
            let scheduled = store.medications.filter { !$0.schedule.isAsNeeded }
            let asNeeded = store.medications.filter(\.schedule.isAsNeeded)

            if store.medications.isEmpty {
                Text("Import your medication list to get dose reminders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !scheduled.isEmpty {
                medicationGroup("Scheduled", scheduled) { formatter.scheduleText($0.schedule).sentenceCased }
            }
            if !asNeeded.isEmpty {
                // No reminders: these are taken only when needed, within their limits.
                medicationGroup("As needed · no reminders", asNeeded) { formatter.warnings(for: $0).first ?? "" }
            }
            if !store.coursesWithRemindersEndingEarly.isEmpty {
                Label("Some course reminders are scheduled only a few days ahead (iOS limits how many can be queued). Opening the app schedules more.",
                      systemImage: "bell.badge")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    /// A titled list of medications, each linking to its details.
    private func medicationGroup(
        _ title: String, _ medications: [Medication], detail: @escaping (Medication) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(medications) { medication in
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name)
                            Text(detail(medication))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func measurementCard(_ reminder: Binding<MeasurementReminder>) -> some View {
        let kind = reminder.wrappedValue.kind
        let isEnabled = reminder.wrappedValue.isEnabled
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(kind.color, in: .rect(cornerRadius: 12))
                    .opacity(isEnabled ? 1 : 0.6)
                Text(kind.label)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Spacer()
                Toggle("\(kind.label) reminders", isOn: reminder.isEnabled)
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

            // Record a reading any time, whether or not reminders are on.
            Button {
                measurementToRecord = kind
            } label: {
                Label("Record Now", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(kind.color)
        }
        .cardStyle()
    }
}

#Preview("Reminders – Cards") {
    RemindersCardView()
        .environment(HealthStore.preview)
}
