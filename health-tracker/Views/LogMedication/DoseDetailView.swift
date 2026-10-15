//
//  DoseDetailView.swift
//  health-tracker
//
//  Read-only details of a logged dose: schedule vs. actual time, amount, status and note.
//

import SwiftUI

struct DoseDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    let log: MedicationLog

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
                        Text("\(log.amountTaken.formatted(.number.precision(.fractionLength(0...4)))) \(log.unit)")
                    }
                    LabeledContent("Prescribed", value: medication.displayDosage)
                    if log.status != .skipped, log.amountTaken != medication.dosage {
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
            }
            .navigationTitle("Dose Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
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

    /// e.g. "250 mg less than prescribed".
    private var differenceDescription: String {
        let diff = log.amountTaken - medication.dosage
        let amount = abs(diff).formatted(.number.precision(.fractionLength(0...4)))
        return "\(amount) \(log.unit) \(diff < 0 ? "less" : "more") than prescribed"
    }
}

#Preview("Dose Details – Partial with Note") {
    DoseDetailView(medication: SampleData.metformin, log: SampleData.medicationLogs[1])
}

#Preview("Dose Details – Extra Dose") {
    DoseDetailView(
        medication: SampleData.vitaminD,
        log: MedicationLog(
            medicationID: SampleData.vitaminD.id, scheduledTime: nil,
            amountTaken: 1000, unit: "IU", status: .extra
        )
    )
}
