//
//  LogMedicationQuickView.swift
//  health-tracker
//
//  Variant C — compact half-sheet: one tap for the common case, details tucked away.
//

import SwiftUI

struct LogMedicationQuickView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    let scheduledTime: TimeOfDay?

    @State private var showDetails = false
    @State private var status: DoseStatus = .partial
    @State private var amount: Double
    @State private var note = ""

    init(medication: Medication, scheduledTime: TimeOfDay? = nil, showDetails: Bool = false) {
        self.medication = medication
        self.scheduledTime = scheduledTime
        _amount = State(initialValue: medication.dosage)
        _showDetails = State(initialValue: showDetails)
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        save(status: .taken, amount: medication.dosage)
                    } label: {
                        Label("Taken", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)

                    Button {
                        save(status: .skipped, amount: 0)
                    } label: {
                        Label("Skip", systemImage: "xmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
            }

            DisclosureGroup("Different amount or add a note", isExpanded: $showDetails) {
                VStack(spacing: 12) {
                    Picker("Status", selection: $status) {
                        ForEach(DoseStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Amount taken")
                        Spacer()
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        Text(medication.unit)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Details") {
                        save(status: status, amount: status == .skipped ? 0 : amount)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(260), .medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.tint, in: .circle)
            VStack(alignment: .leading) {
                Text(medication.name)
                    .font(.title3.bold())
                Text(scheduledTime.map { "\(medication.displayDosage) · due \($0.displayText)" }
                     ?? medication.displayDosage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func save(status: DoseStatus, amount: Double) {
        store.logDose(MedicationLog(
            medicationID: medication.id,
            scheduledTime: scheduledTime,
            amountTaken: amount,
            unit: medication.unit,
            status: status,
            note: note
        ))
        dismiss()
    }
}

/// Mimics the half-sheet presentation, since preview snapshots don't capture real sheets.
private struct SheetMockup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            content
                .frame(maxWidth: .infinity)
                .background(.background, in: .rect(cornerRadius: 36))
                .shadow(color: .black.opacity(0.15), radius: 20)
                .padding(8)
        }
    }
}

#Preview("Log Medication – Quick Sheet") {
    SheetMockup {
        LogMedicationQuickView(medication: SampleData.lisinopril, scheduledTime: TimeOfDay(hour: 8, minute: 0))
            .frame(height: 260)
    }
    .environment(HealthStore.preview)
}

#Preview("Log Medication – Quick Sheet (Details)") {
    SheetMockup {
        LogMedicationQuickView(
            medication: SampleData.metformin,
            scheduledTime: TimeOfDay(hour: 20, minute: 0),
            showDetails: true
        )
        .frame(height: 480)
    }
    .environment(HealthStore.preview)
}
