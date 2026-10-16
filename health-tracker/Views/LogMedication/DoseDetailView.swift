//
//  DoseDetailView.swift
//  health-tracker
//
//  Details of a logged dose: schedule vs. actual time, amount, status and note,
//  with Edit and Delete.
//

import SwiftUI

struct DoseDetailView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    /// The dose as it was when opened; `log` shows the latest version after edits.
    private let initialLog: MedicationLog
    @State private var isEditing = false

    init(medication: Medication, log: MedicationLog) {
        self.medication = medication
        initialLog = log
    }

    private var log: MedicationLog {
        store.medicationLogs.first { $0.id == initialLog.id } ?? initialLog
    }

    private var isDeleted: Bool {
        !store.medicationLogs.contains { $0.id == initialLog.id }
    }

    private let formatter = PrescriptionFormatter()

    /// Doses within this many minutes of the scheduled time count as on time.
    private static let onTimeWindowMinutes = 15

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: log.status.symbol)
                            .font(.title)
                            .foregroundStyle(log.status.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name)
                                .font(.title3.bold())
                            Text(log.status.label)
                                .foregroundStyle(log.status.color)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if log.confirmedOverLimit {
                        Label("Logged over the as-needed limit", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        Text(formatter.instruction(for: medication))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Timing") {
                    LabeledContent("Scheduled") {
                        Text(log.scheduledDate?.formatted(date: .abbreviated, time: .shortened)
                             ?? "Not scheduled (extra dose)")
                    }
                    LabeledContent("Taken") {
                        Text(log.takenAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let timing = timingDescription {
                        LabeledContent("Timing") {
                            Text(timing.text).foregroundStyle(timing.color)
                        }
                    }
                }

                Section("Dose") {
                    LabeledContent("Amount taken") {
                        Text(log.status == .skipped ? "None" : formatter.doseText(for: medication, quantity: log.quantityTaken))
                    }
                    LabeledContent("Prescribed", value: formatter.doseText(for: medication))
                    if log.status != .skipped, log.quantityTaken != medication.quantity {
                        LabeledContent("Difference") {
                            Text(differenceDescription)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Note") {
                    if log.note.isEmpty {
                        Text("No note")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(log.note)
                    }
                }

                DeleteEntrySection(
                    entryName: "Dose",
                    message: log.scheduledTime == nil
                        ? "This can't be undone."
                        : "The scheduled dose will show as not logged again. This can't be undone."
                ) {
                    store.deleteDose(id: log.id)
                }
            }
            .navigationTitle("Dose Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { isEditing = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .sheet(isPresented: $isEditing) {
                LogMedicationView(editing: log)
            }
            // Deleted here or from the Edit sheet: nothing left to show.
            .onChange(of: isDeleted) {
                if isDeleted { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// How the actual time compares to the scheduled time, e.g. "25 min late".
    private var timingDescription: (text: String, color: Color)? {
        guard let scheduledDate = log.scheduledDate, log.status != .skipped else { return nil }
        let minutes = Int(log.takenAt.timeIntervalSince(scheduledDate) / 60)
        if abs(minutes) <= Self.onTimeWindowMinutes {
            return ("On time", .green)
        }
        let duration = Duration.seconds(abs(minutes) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return minutes > 0 ? ("\(duration) late", .orange) : ("\(duration) early", .orange)
    }

    /// e.g. "½ tablet (250 mg) less than prescribed".
    private var differenceDescription: String {
        let diff = log.quantityTaken - medication.quantity
        return "\(formatter.doseText(for: medication, quantity: abs(diff))) \(diff < 0 ? "less" : "more") than prescribed"
    }
}

#Preview("Dose Details – Partial with Note") {
    DoseDetailView(medication: SampleData.metformin, log: SampleData.medicationLogs[1])
        .environment(HealthStore.preview)
}

#Preview("Dose Details – Extra Dose") {
    DoseDetailView(
        medication: SampleData.vitaminD,
        log: MedicationLog(
            medicationID: SampleData.vitaminD.id, scheduledTime: nil,
            quantityTaken: 1, status: .extra
        )
    )
    .environment(HealthStore.preview)
}
