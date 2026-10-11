//
//  LogMedicationCardView.swift
//  health-tracker
//
//  Variant B — large tappable medication tiles, chip-style status, and a stepper for the amount.
//

import SwiftUI

struct LogMedicationCardView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var medicationID: Medication.ID?
    @State private var scheduledTime: TimeOfDay?
    @State private var status: DoseStatus = .taken
    @State private var amount: Double = 0
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    medicationGrid
                    if let medication {
                        amountCard(for: medication)
                    }
                    statusChips
                    notesCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log a Dose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Save Dose")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(medication == nil)
                .padding()
            }
        }
    }

    private var medicationGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which medication?")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(store.medications) { med in
                    let isSelected = med.id == medicationID
                    Button {
                        medicationID = med.id
                        amount = med.dosage
                        scheduledTime = med.times.first
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "pills.fill")
                                .font(.title2)
                            Text(med.name)
                                .font(.headline)
                            Text(med.displayDosage)
                                .font(.subheadline)
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(
                            isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.background),
                            in: .rect(cornerRadius: 16)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func amountCard(for medication: Medication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much did you take?")
                .font(.headline)
            Stepper(value: $amount, in: 0...(medication.dosage * 4), step: medication.dosage / 2) {
                Text("\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(medication.unit)")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
            }
            HStack {
                ForEach([0.5, 1, 2], id: \.self) { factor in
                    Button(factor == 1 ? "As prescribed" : "\(factor.formatted())×") {
                        amount = medication.dosage * factor
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if !medication.times.isEmpty {
                Picker("For dose", selection: $scheduledTime) {
                    Text("Unscheduled").tag(TimeOfDay?.none)
                    ForEach(medication.times) { time in
                        Text(time.displayText).tag(Optional(time))
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 16))
        .animation(.default, value: amount)
    }

    private var statusChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)
            HStack {
                ForEach(DoseStatus.allCases) { option in
                    Button {
                        status = option
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: option.symbol)
                                .font(.title3)
                            Text(option.label)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(status == option ? .white : option.color)
                    .background(status == option ? option.color : option.color.opacity(0.15),
                                in: .rect(cornerRadius: 14))
                    .accessibilityAddTraits(status == option ? .isSelected : [])
                }
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $note)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background, in: .rect(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Anything worth remembering?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func save() {
        guard let medication else { return }
        store.logDose(MedicationLog(
            medicationID: medication.id,
            scheduledTime: scheduledTime,
            amountTaken: status == .skipped ? 0 : amount,
            unit: medication.unit,
            status: status,
            note: note
        ))
        dismiss()
    }
}

#Preview("Log Medication – Cards") {
    LogMedicationCardView(medication: SampleData.metformin, scheduledTime: TimeOfDay(hour: 20, minute: 0))
        .environment(HealthStore.preview)
}
