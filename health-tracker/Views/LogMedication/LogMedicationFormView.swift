//
//  LogMedicationFormView.swift
//  health-tracker
//
//  Variant A — classic grouped Form.
//

import SwiftUI

struct LogMedicationFormView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var medicationID: Medication.ID?
    @State private var scheduledTime: TimeOfDay?
    @State private var status: DoseStatus = .taken
    @State private var amount: Double = 0
    @State private var takenAt: Date = .now
    @State private var note = ""

    init(medication: Medication? = nil, scheduledTime: TimeOfDay? = nil) {
        _medicationID = State(initialValue: medication?.id)
        _scheduledTime = State(initialValue: scheduledTime)
        _amount = State(initialValue: medication?.dosage ?? 0)
    }

    private var medication: Medication? {
        medicationID.flatMap(store.medication(for:))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Picker("Medication", selection: $medicationID) {
                        Text("Choose…").tag(Medication.ID?.none)
                        ForEach(store.medications) { med in
                            Text(med.name).tag(Optional(med.id))
                        }
                    }
                    if let medication {
                        Picker("Scheduled dose", selection: $scheduledTime) {
                            Text("Unscheduled").tag(TimeOfDay?.none)
                            ForEach(medication.times) { time in
                                Text(time.displayText).tag(Optional(time))
                            }
                        }
                        LabeledContent("Prescribed", value: medication.displayDosage)
                    }
                }

                Section("What you actually took") {
                    Picker("Status", selection: $status) {
                        ForEach(DoseStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    if status != .skipped {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(medication?.unit ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Time", selection: $takenAt)
                }

                Section("Notes") {
                    TextField("Side effects, reason for skipping, etc.", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(medication == nil)
                }
            }
            .onAppear {
                if medicationID == nil, let first = store.medications.first {
                    medicationID = first.id
                    amount = first.dosage
                }
            }
            .onChange(of: medicationID) {
                amount = medication?.dosage ?? 0
                scheduledTime = nil
            }
        }
    }

    private func save() {
        guard let medication else { return }
        store.logDose(MedicationLog(
            medicationID: medication.id,
            scheduledTime: scheduledTime,
            takenAt: takenAt,
            amountTaken: status == .skipped ? 0 : amount,
            unit: medication.unit,
            status: status,
            note: note
        ))
        dismiss()
    }
}

#Preview("Log Medication – Form") {
    LogMedicationFormView(medication: SampleData.metformin, scheduledTime: TimeOfDay(hour: 20, minute: 0))
        .environment(HealthStore.preview)
}
