//
//  TodayListView.swift
//  health-tracker
//
//  Variant A — inset grouped List, sections for doses, measurements and symptoms.
//

import SwiftUI

struct TodayListView: View {
    @Environment(HealthStore.self) private var store

    @State private var doseToLog: DoseSlot?
    @State private var isLoggingSymptom = false
    @State private var isLoggingExtraDose = false

    var body: some View {
        let doses = store.todaysDoses()
        let takenCount = doses.filter { $0.log != nil }.count

        NavigationStack {
            List {
                Section {
                    ForEach(doses) { slot in
                        Button {
                            doseToLog = slot
                        } label: {
                            doseRow(slot)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            if slot.log == nil {
                                Button("Taken", systemImage: "checkmark") {
                                    quickLog(slot)
                                }
                                .tint(.green)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Medications")
                        Spacer()
                        Text("\(takenCount) of \(doses.count) logged")
                    }
                } footer: {
                    Text("Swipe right to mark a dose as taken. Tap to log details.")
                }

                Section("Measurements") {
                    let measurements = store.measurementReminders.filter(\.isEnabled)
                    if measurements.isEmpty {
                        Text("No measurement reminders set.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(measurements) { reminder in
                        HStack {
                            Label(reminder.kind.label, systemImage: reminder.kind.symbol)
                                .foregroundStyle(reminder.kind.color)
                            Spacer()
                            Text(reminder.times.map(\.displayText).formatted(.list(type: .and)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Symptoms Today") {
                    ForEach(store.todaysSymptoms()) { log in
                        HStack {
                            Label(log.displayName, systemImage: log.type.symbol)
                            Spacer()
                            SeverityBadge(severity: log.severity)
                            Text(log.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Log a Symptom", systemImage: "plus") {
                        isLoggingSymptom = true
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                Menu("Add", systemImage: "plus") {
                    Button("Log Medication", systemImage: "pills") { isLoggingExtraDose = true }
                    Button("Log Symptom", systemImage: "stethoscope") { isLoggingSymptom = true }
                }
            }
            .sheet(item: $doseToLog) { slot in
                LogMedicationFormView(medication: slot.medication, scheduledTime: slot.time)
            }
            .sheet(isPresented: $isLoggingExtraDose) {
                LogMedicationFormView()
            }
            .sheet(isPresented: $isLoggingSymptom) {
                LogSymptomFormView()
            }
        }
    }

    private func doseRow(_ slot: DoseSlot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.medication.name)
                    .font(.body.weight(.medium))
                Text("\(slot.medication.displayDosage) · \(slot.time.displayText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DoseStatusLabel(slot: slot)
                .font(.subheadline)
        }
    }

    private func quickLog(_ slot: DoseSlot) {
        store.logDose(MedicationLog(
            medicationID: slot.medication.id,
            scheduledTime: slot.time,
            amountTaken: slot.medication.dosage,
            unit: slot.medication.unit,
            status: .taken
        ))
    }
}

#Preview("Today – List") {
    TodayListView()
        .environment(HealthStore.preview)
}
