//
//  LogMeasurementView.swift
//  health-tracker
//
//  Sheet for recording a reading such as blood pressure or oxygen saturation.
//

import SwiftUI

struct LogMeasurementView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The reminder slot being satisfied; when set, the measurement type is fixed.
    let scheduledTime: TimeOfDay?
    /// The day being recorded for (today, or a past day chosen on the timeline).
    let day: Date

    @State private var kind: MeasurementKind
    /// One entry per `kind.fields`; `nil` until the user types a number.
    @State private var values: [Double?]
    @State private var takenAt: Date
    @State private var note = ""

    init(kind: MeasurementKind, scheduledTime: TimeOfDay? = nil, day: Date = .now) {
        self.scheduledTime = scheduledTime
        self.day = day
        _takenAt = State(initialValue: .defaultLogTime(on: day, scheduled: scheduledTime))
        _kind = State(initialValue: kind)
        _values = State(initialValue: Array(repeating: nil, count: kind.fields.count))
    }

    private var fields: [MeasurementField] { kind.fields }

    /// Messages for values outside the plausible range (likely typos).
    private var problems: [String] {
        zip(fields, values).compactMap { field, value in
            guard let value, !field.validRange.contains(value) else { return nil }
            let low = field.validRange.lowerBound.formatted()
            let high = field.validRange.upperBound.formatted()
            return "\(field.label) should be between \(low) and \(high) \(field.unit)."
        }
    }

    private var canSave: Bool {
        values.count == fields.count && values.allSatisfy { $0 != nil } && problems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if scheduledTime == nil {
                        Picker("Measurement", selection: $kind) {
                            ForEach(MeasurementKind.allCases) { kind in
                                Label(kind.label, systemImage: kind.symbol).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        HStack {
                            Text("Measurement")
                            Spacer()
                            Image(systemName: kind.symbol)
                                .foregroundStyle(kind.color)
                            Text(kind.label)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let scheduledTime {
                        LabeledContent("Reminder") {
                            Text(scheduledTime.date(on: day).formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                Section {
                    ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                        HStack {
                            Text(field.label)
                            Spacer()
                            TextField(field.label, value: valueBinding(at: index), format: .number,
                                      prompt: Text("0"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(field.unit)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .leading)
                        }
                    }
                } header: {
                    Text("Reading")
                } footer: {
                    if !problems.isEmpty {
                        Text(problems.joined(separator: "\n"))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    DatePicker("Taken at", selection: $takenAt, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Position, arm used, how you felt…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Record Reading")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: save)
            }
            .onChange(of: kind) {
                values = Array(repeating: nil, count: kind.fields.count)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Bounds-safe binding: when the measurement type changes, the new fields can render
    /// before `values` is resized in `onChange`.
    private func valueBinding(at index: Int) -> Binding<Double?> {
        Binding(
            get: { values.indices.contains(index) ? values[index] : nil },
            set: { newValue in
                if values.indices.contains(index) { values[index] = newValue }
            }
        )
    }

    private func save() {
        store.logMeasurement(MeasurementLog(
            kind: kind,
            values: values.compactMap { $0 },
            unit: fields.first?.unit ?? "",
            scheduledTime: scheduledTime,
            scheduledDay: day,
            takenAt: takenAt,
            note: note
        ))
        dismiss()
    }
}

#Preview("Record Measurement – Blood Pressure") {
    LogMeasurementView(kind: .bloodPressure, scheduledTime: TimeOfDay(hour: 19, minute: 30))
        .environment(HealthStore.preview)
}

#Preview("Record Measurement – Unscheduled") {
    LogMeasurementView(kind: .oxygenSaturation)
        .environment(HealthStore.preview)
}
