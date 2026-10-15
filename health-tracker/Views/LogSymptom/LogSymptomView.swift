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
    @State private var note = ""

    init(type: SymptomType = .headache, day: Date = .now) {
        self.day = day
        _type = State(initialValue: type)
        _date = State(initialValue: .defaultLogTime(on: day, scheduled: nil))
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
                    DatePicker("When", selection: $date, in: ...Date.now)
                }

                Section("Notes") {
                    TextField("Triggers, duration, what helped…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Log Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: canSave, action: save)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        store.logSymptom(SymptomLog(
            type: type,
            customName: customName.trimmingCharacters(in: .whitespaces),
            severity: severity,
            date: date,
            note: note
        ))
        dismiss()
    }
}

#Preview("Log Symptom – Dialog") {
    LogSymptomView(type: .nausea)
        .environment(HealthStore.preview)
}
