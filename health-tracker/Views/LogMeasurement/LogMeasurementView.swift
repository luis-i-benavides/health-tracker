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
    /// What's typed in each `kind.fields` entry. Kept as text (not a number-formatted field,
    /// which only takes the value on Return — and the decimal pad has no Return key).
    @State private var texts: [String]
    @State private var takenAt: Date
    /// Whether the user changed the time; until then a reading for today is logged at Save time.
    @State private var takenAtEdited = false
    @State private var note = ""
    /// The reading being edited; `nil` when recording a new one.
    private let editing: MeasurementLog?

    init(kind: MeasurementKind, scheduledTime: TimeOfDay? = nil, day: Date = .now) {
        self.scheduledTime = scheduledTime
        self.day = day
        editing = nil
        _takenAt = State(initialValue: .defaultLogTime(on: day, scheduled: scheduledTime))
        _kind = State(initialValue: kind)
        _texts = State(initialValue: Array(repeating: "", count: kind.fields.count))
    }

    /// Edits a recorded reading, prefilled with its values.
    init(editing log: MeasurementLog) {
        scheduledTime = log.scheduledTime
        day = log.scheduledDay
        editing = log
        _takenAt = State(initialValue: log.takenAt)
        // Keep the recorded time unless the user changes it.
        _takenAtEdited = State(initialValue: true)
        _kind = State(initialValue: log.kind)
        _texts = State(initialValue: log.values.map {
            $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        })
        _note = State(initialValue: log.note)
    }

    /// The type can be changed only for a new, unscheduled reading.
    private var isKindFixed: Bool { scheduledTime != nil || editing != nil }

    private var fields: [MeasurementField] { kind.fields }

    /// The typed numbers; `nil` where a field is empty or isn't a number.
    /// Parsed for the current locale, so "36,6" works where a comma is the decimal separator.
    private var values: [Double?] {
        texts.map { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return try? Double(trimmed, format: .number)
        }
    }

    /// Messages for text that isn't a number, or values outside the plausible range (likely typos).
    private var problems: [String] {
        zip(fields, zip(texts, values)).compactMap { field, entry in
            let (text, value) = entry
            if value == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return "\(field.label) must be a number."
            }
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
                    if !isKindFixed {
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
                            TextField(field.label, text: textBinding(at: index), prompt: Text("0"))
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
                    DatePicker("Taken at", selection: $takenAt.onSet { takenAtEdited = true }, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Position, arm used, how you felt…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let editing {
                    DeleteEntrySection(
                        entryName: "Reading",
                        message: editing.scheduledTime == nil
                            ? "This can't be undone."
                            : "The reminder will show as not recorded again. This can't be undone."
                    ) {
                        store.deleteMeasurement(id: editing.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(editing == nil ? "Record Reading" : "Edit Reading")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: save)
            }
            .onChange(of: kind) {
                texts = Array(repeating: "", count: kind.fields.count)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Bounds-safe binding: when the measurement type changes, the new fields can render
    /// before `texts` is resized in `onChange`.
    private func textBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { texts.indices.contains(index) ? texts[index] : "" },
            set: { newValue in
                if texts.indices.contains(index) { texts[index] = newValue }
            }
        )
    }

    private func save() {
        let log = MeasurementLog(
            id: editing?.id ?? UUID(),
            kind: kind,
            values: values.compactMap { $0 },
            // An edited reading keeps the unit it was recorded in.
            unit: editing?.unit ?? fields.first?.unit ?? "",
            scheduledTime: scheduledTime,
            scheduledDay: day,
            takenAt: .logTime(chosen: takenAt, edited: takenAtEdited, day: day),
            note: note
        )
        if editing == nil {
            store.logMeasurement(log)
        } else {
            store.updateMeasurement(log)
        }
        dismiss()
    }
}

#Preview("Edit Reading") {
    LogMeasurementView(editing: SampleData.measurementLogs[0])
        .environment(HealthStore.preview)
}

#Preview("Record Measurement – Blood Pressure") {
    LogMeasurementView(kind: .bloodPressure, scheduledTime: TimeOfDay(hour: 19, minute: 30))
        .environment(HealthStore.preview)
}

#Preview("Record Measurement – Unscheduled") {
    LogMeasurementView(kind: .oxygenSaturation)
        .environment(HealthStore.preview)
}
