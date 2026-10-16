//
//  LogSymptomView.swift
//  health-tracker
//
//  Sheet for logging a symptom; laid out like the Record Reading dialog.
//

import SwiftUI

struct LogSymptomView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The day being logged for (today, or a past day chosen on the timeline).
    let day: Date

    @State private var type: SymptomType
    @State private var customName = ""
    /// 1–10 intensity, mapped to mild / moderate / severe.
    @State private var score: Double = 5
    @State private var date: Date
    /// Whether the user changed the time; until then a symptom for today is logged at Save time.
    @State private var dateEdited = false
    @State private var note = ""
    /// The symptom being edited; `nil` when logging a new one.
    private let editing: SymptomLog?

    init(type: SymptomType = .headache, day: Date = .now) {
        self.day = day
        editing = nil
        _type = State(initialValue: type)
        _date = State(initialValue: .defaultLogTime(on: day, scheduled: nil))
    }

    /// Edits a logged symptom, prefilled with what was recorded.
    init(editing log: SymptomLog) {
        day = log.date
        editing = log
        _type = State(initialValue: log.type)
        _customName = State(initialValue: log.customName)
        // Only the severity is stored, so start the slider in the middle of its range.
        _score = State(initialValue: Self.score(for: log.severity))
        _date = State(initialValue: log.date)
        // Keep the recorded time unless the user changes it.
        _dateEdited = State(initialValue: true)
        _note = State(initialValue: log.note)
    }

    private static func score(for severity: Severity) -> Double {
        switch severity {
        case .mild: 2
        case .moderate: 5
        case .severe: 8
        }
    }

    private var severity: Severity { Severity(score: Int(score)) }

    private var canSave: Bool {
        type != .other || !customName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Symptom", selection: $type) {
                        ForEach(SymptomType.allCases) { type in
                            Label(type.label, systemImage: type.symbol).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    if type == .other {
                        TextField("Describe the symptom", text: $customName)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Intensity")
                            Spacer()
                            Text("\(Int(score))/10")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            SeverityBadge(severity: severity)
                        }
                        Slider(value: $score, in: 1...10, step: 1) {
                            Text("Intensity")
                        } minimumValueLabel: {
                            Text("1")
                        } maximumValueLabel: {
                            Text("10")
                        }
                        .tint(severity.color)
                    }
                } header: {
                    Text("Severity")
                } footer: {
                    Text("1–3 mild · 4–6 moderate · 7–10 severe")
                }

                Section {
                    DatePicker("When", selection: $date.onSet { dateEdited = true }, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Triggers, duration, what helped…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let editing {
                    DeleteEntrySection(entryName: "Symptom") {
                        store.deleteSymptom(id: editing.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(editing == nil ? "Log Symptom" : "Edit Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: save)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let log = SymptomLog(
            id: editing?.id ?? UUID(),
            type: type,
            customName: type == .other ? customName.trimmingCharacters(in: .whitespaces) : "",
            severity: severity,
            date: .logTime(chosen: date, edited: dateEdited, day: day),
            note: note
        )
        if editing == nil {
            store.logSymptom(log)
        } else {
            store.updateSymptom(log)
        }
        dismiss()
    }
}

#Preview("Edit Symptom") {
    LogSymptomView(editing: SampleData.symptomLogs[0])
        .environment(HealthStore.preview)
}

#Preview("Log Symptom – Dialog") {
    LogSymptomView(type: .nausea)
        .environment(HealthStore.preview)
}
