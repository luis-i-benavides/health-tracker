//
//  LogMedicationView.swift
//  health-tracker
//
//  Sheet for logging a dose; laid out like the Log Symptom and Record Reading dialogs.
//

import SwiftUI

struct LogMedicationView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The day being logged for (today, or a past day chosen on the timeline).
    let day: Date
    /// Opened from a specific scheduled dose: the medication and slot are fixed.
    private let isForScheduledDose: Bool

    @State private var medicationID: Medication.ID?
    /// The scheduled slot this dose satisfies; `nil` means an extra, unscheduled dose.
    @State private var scheduledTime: TimeOfDay?
    @State private var status: DoseStatus
    @State private var amount: Double?
    @State private var takenAt: Date
    @State private var note = ""

    init(medication: Medication? = nil, scheduledTime: TimeOfDay? = nil, day: Date = .now) {
        self.day = day
        isForScheduledDose = scheduledTime != nil
        _medicationID = State(initialValue: medication?.id)
        _scheduledTime = State(initialValue: scheduledTime)
        _status = State(initialValue: scheduledTime == nil ? .extra : .taken)
        _amount = State(initialValue: medication?.dosage)
        _takenAt = State(initialValue: .defaultLogTime(on: day, scheduled: scheduledTime))
    }

    private var medication: Medication? {
        medicationID.flatMap(store.medication(for:))
    }

    private var canSave: Bool {
        guard medication != nil else { return false }
        return status == .skipped || (amount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isForScheduledDose, let medication {
                        LabeledContent("Medication", value: medication.name)
                        if let scheduledTime {
                            LabeledContent("Scheduled") {
                                Text(scheduledTime.date(on: day).formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    } else if store.medications.isEmpty {
                        Text("Import your medication list from the Import tab first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Medication", selection: $medicationID) {
                            Text("Choose…").tag(Medication.ID?.none)
                            ForEach(store.medications) { med in
                                Text(med.name).tag(Optional(med.id))
                            }
                        }
                        .pickerStyle(.menu)
                        if let medication {
                            Picker("For dose", selection: $scheduledTime) {
                                Text("Extra (unscheduled)").tag(TimeOfDay?.none)
                                ForEach(medication.times) { time in
                                    Text("\(time.displayText) dose").tag(Optional(time))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if let medication {
                        LabeledContent("Prescribed", value: medication.displayDosage)
                    }
                }

                Section("What you took") {
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
                            TextField("Amount", value: $amount, format: .number, prompt: Text("0"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(medication?.unit ?? "")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .leading)
                        }
                    }
                }

                Section {
                    DatePicker("Taken at", selection: $takenAt, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Side effects, reason for skipping…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: save)
            }
            .onAppear {
                // Opened without a medication: preselect the first one.
                if medicationID == nil, let first = store.medications.first {
                    medicationID = first.id
                    amount = first.dosage
                }
            }
            .onChange(of: medicationID) {
                guard !isForScheduledDose else { return }
                amount = medication?.dosage
                scheduledTime = nil
            }
            // Keep the status consistent with whether the dose is scheduled.
            .onChange(of: scheduledTime) {
                if scheduledTime == nil {
                    status = .extra
                } else if status == .extra {
                    status = .taken
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let medication else { return }
        store.logDose(MedicationLog(
            medicationID: medication.id,
            scheduledTime: scheduledTime,
            scheduledDay: day,
            takenAt: takenAt,
            amountTaken: status == .skipped ? 0 : (amount ?? medication.dosage),
            unit: medication.unit,
            status: status,
            note: note
        ))
        dismiss()
    }
}

#Preview("Log Medication – Scheduled Dose") {
    LogMedicationView(medication: SampleData.metformin, scheduledTime: TimeOfDay(hour: 20, minute: 0))
        .environment(HealthStore.preview)
}

#Preview("Log Medication – Extra Dose") {
    LogMedicationView(medication: SampleData.vitaminD)
        .environment(HealthStore.preview)
}
