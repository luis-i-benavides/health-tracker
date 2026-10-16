//
//  LogMedicationView.swift
//  health-tracker
//
//  Sheet for logging a dose; laid out like the Log Symptom and Record Reading dialogs.
//  The amount is entered in units (tablets, puffs, mL); the drug amount is shown alongside.
//

import SwiftUI

struct LogMedicationView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The day being logged for (today, or a past day chosen on the timeline).
    let day: Date
    /// Opened from a specific scheduled dose, or editing a logged one: the medication and slot are fixed.
    private let isForScheduledDose: Bool
    /// The logged dose being edited; `nil` when logging a new dose.
    private let editing: MedicationLog?

    @State private var medicationID: Medication.ID?
    /// The scheduled slot this dose satisfies; `nil` means an extra, unscheduled dose.
    @State private var scheduledTime: TimeOfDay?
    @State private var status: DoseStatus
    @State private var quantity: Double
    @State private var takenAt: Date
    /// Whether the user changed the time; until then a dose for today is logged at Save time.
    @State private var takenAtEdited = false
    @State private var note = ""
    /// As-needed limit warnings awaiting the user's confirmation.
    @State private var pendingWarnings: [AsNeededWarning] = []

    private let formatter = PrescriptionFormatter()

    init(medication: Medication? = nil, scheduledTime: TimeOfDay? = nil, day: Date = .now) {
        self.day = day
        isForScheduledDose = scheduledTime != nil
        editing = nil
        _medicationID = State(initialValue: medication?.id)
        _scheduledTime = State(initialValue: scheduledTime)
        _status = State(initialValue: scheduledTime == nil ? .extra : .taken)
        _quantity = State(initialValue: medication?.quantity ?? 1)
        _takenAt = State(initialValue: .defaultLogTime(on: day, scheduled: scheduledTime))
    }

    /// Edits a logged dose, prefilled with what was recorded.
    init(editing log: MedicationLog) {
        day = log.scheduledDay
        isForScheduledDose = true
        editing = log
        _medicationID = State(initialValue: log.medicationID)
        _scheduledTime = State(initialValue: log.scheduledTime)
        _status = State(initialValue: log.status)
        _quantity = State(initialValue: log.status == .skipped ? 1 : log.quantityTaken)
        _takenAt = State(initialValue: log.takenAt)
        // Keep the recorded time unless the user changes it.
        _takenAtEdited = State(initialValue: true)
        _note = State(initialValue: log.note)
    }

    private var medication: Medication? {
        medicationID.flatMap(store.medication(for:))
    }

    private var effectiveTakenAt: Date {
        .logTime(chosen: takenAt, edited: takenAtEdited, day: day)
    }

    private var canSave: Bool {
        medication != nil && (status == .skipped || quantity > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                medicationSection
                if let medication, medication.schedule.isAsNeeded {
                    asNeededSection(for: medication)
                }
                takenSection

                Section {
                    DatePicker("Taken at", selection: $takenAt.onSet { takenAtEdited = true }, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Side effects, reason for skipping…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let editing {
                    DeleteEntrySection(
                        entryName: "Dose",
                        message: editing.scheduledTime == nil
                            ? "This can't be undone."
                            : "The scheduled dose will show as not logged again. This can't be undone."
                    ) {
                        store.deleteDose(id: editing.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(editing == nil ? "Log Medication" : "Edit Dose")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: attemptSave)
            }
            .alert("Over the Limit", isPresented: Binding(
                get: { !pendingWarnings.isEmpty },
                set: { if !$0 { pendingWarnings = [] } }
            )) {
                Button("Log Dose", role: .destructive) { save(confirmedOverLimit: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pendingWarnings.map { formatter.warningText($0) }.joined(separator: "\n\n")
                     + "\n\nLog it anyway if you've already taken it.")
            }
            .onAppear {
                // Opened without a medication: preselect the first one.
                if medicationID == nil, let first = store.medications.first {
                    medicationID = first.id
                    quantity = first.quantity
                }
                // Editing a skipped dose: offer the prescribed amount if it's changed to taken.
                if editing?.status == .skipped, let medication {
                    quantity = medication.quantity
                }
            }
            .onChange(of: medicationID) {
                guard !isForScheduledDose else { return }
                quantity = medication?.quantity ?? 1
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

    // MARK: - Sections

    @ViewBuilder
    private var medicationSection: some View {
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
                if let medication, !medication.schedule.isAsNeeded {
                    Picker("For dose", selection: $scheduledTime) {
                        Text("Extra (unscheduled)").tag(TimeOfDay?.none)
                        ForEach(medication.times) { time in
                            Text("\(formatter.timeText(time)) dose").tag(Optional(time))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } footer: {
            if let medication {
                Text(formatter.instruction(for: medication))
            }
        }
    }

    private func asNeededSection(for medication: Medication) -> some View {
        Section("As needed") {
            if let limits = store.asNeededStatus(for: medication, at: effectiveTakenAt, excluding: editing?.id) {
                let isAtMax = limits.remainingDoses == 0
                Label(formatter.statusText(limits), systemImage: isAtMax ? "exclamationmark.triangle.fill" : "clock")
                    .foregroundStyle(isAtMax ? .orange : .primary)
                Text(formatter.nextDoseText(limits))
                    .foregroundStyle(limits.nextAllowed == nil ? .green : .orange)
            }
        }
    }

    private var takenSection: some View {
        Section("What you took") {
            Picker("Status", selection: $status) {
                ForEach(DoseStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.segmented)

            if status != .skipped, let medication {
                let step = medication.form.isSplittable || medication.form == .milliliter ? 0.5 : 1
                Stepper(value: $quantity, in: step...max(20, medication.quantity * 4), step: step) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text(formatter.doseText(for: medication, quantity: quantity))
                            .monospacedDigit()
                            .foregroundStyle(quantity == medication.quantity ? Color.primary : Color.orange)
                    }
                }
            }
        }
    }

    // MARK: - Saving

    /// Saves, or first asks for confirmation when an as-needed limit would be exceeded.
    private func attemptSave() {
        guard let medication else { return }
        // When editing, the dose itself isn't counted against the limits.
        let warnings = status == .skipped
            ? []
            : store.asNeededWarnings(forDoseOf: medication, at: effectiveTakenAt, excluding: editing?.id)
        if warnings.isEmpty {
            save(confirmedOverLimit: false)
        } else if editing?.confirmedOverLimit == true {
            // Already confirmed when it was logged; don't ask again for an edit.
            save(confirmedOverLimit: true)
        } else {
            pendingWarnings = warnings
        }
    }

    private func save(confirmedOverLimit: Bool) {
        guard let medication else { return }
        let log = MedicationLog(
            id: editing?.id ?? UUID(),
            medicationID: medication.id,
            scheduledTime: scheduledTime,
            scheduledDay: day,
            takenAt: effectiveTakenAt,
            quantityTaken: status == .skipped ? 0 : quantity,
            status: status,
            note: note,
            confirmedOverLimit: confirmedOverLimit
        )
        if editing == nil {
            store.logDose(log)
        } else {
            store.updateDose(log)
        }
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

#Preview("Edit Dose") {
    LogMedicationView(editing: SampleData.medicationLogs[1])
        .environment(HealthStore.preview)
}

#Preview("Log Medication – As Needed") {
    LogMedicationView(medication: SampleData.albuterol)
        .environment(HealthStore.preview)
}
