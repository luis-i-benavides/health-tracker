//
//  LogSymptomFormView.swift
//  health-tracker
//
//  Variant A — classic Form with a dropdown and segmented severity.
//

import SwiftUI

struct LogSymptomFormView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var type: SymptomType = .headache
    @State private var customName = ""
    @State private var severity: Severity = .mild
    @State private var date: Date = .now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptom") {
                    SymptomPicker(selection: $type)
                    if type == .other {
                        TextField("Describe the symptom", text: $customName)
                    }
                }

                Section {
                    Picker("Severity", selection: $severity) {
                        ForEach(Severity.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Severity")
                } footer: {
                    Text("Mild: noticeable. Moderate: affects activities. Severe: stops activities.")
                }

                Section {
                    DatePicker("When", selection: $date)
                }

                Section("Notes") {
                    TextField("Triggers, duration, what helped…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        store.logSymptom(SymptomLog(
                            type: type, customName: customName, severity: severity, date: date, note: note
                        ))
                        dismiss()
                    }
                    .disabled(type == .other && customName.isEmpty)
                }
            }
        }
    }
}

#Preview("Log Symptom – Form") {
    LogSymptomFormView()
        .environment(HealthStore.preview)
}
