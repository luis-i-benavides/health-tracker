//
//  LogSymptomCompactView.swift
//  health-tracker
//
//  Variant C — compact single screen: dropdown, 1–10 slider mapped to severity,
//  and today's symptom history below.
//

import SwiftUI

struct LogSymptomCompactView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When presented as a sheet (e.g. from the timeline), show a Done button and close after logging.
    var isSheet = false

    @State private var type: SymptomType = .headache
    @State private var customName = ""
    @State private var score: Double = 5
    @State private var note = ""

    private var severity: Severity { Severity(score: Int(score)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SymptomPicker(selection: $type)
                    if type == .other {
                        TextField("Describe the symptom", text: $customName)
                    }

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

                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(2...4)

                    Button("Log Symptom", systemImage: "plus.circle.fill", action: save)
                        .disabled(type == .other && customName.isEmpty)
                }

                Section("Earlier") {
                    ForEach(store.symptomLogs.sorted { $0.date > $1.date }) { log in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: log.type.symbol)
                                .foregroundStyle(log.severity.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.displayName)
                                if !log.note.isEmpty {
                                    Text(log.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(log.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Symptoms")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm) { dismiss() }
                    }
                }
            }
        }
    }

    private func save() {
        store.logSymptom(SymptomLog(type: type, customName: customName, severity: severity, note: note))
        note = ""
        customName = ""
        score = 5
        if isSheet { dismiss() }
    }
}

#Preview("Log Symptom – Compact") {
    LogSymptomCompactView()
        .environment(HealthStore.preview)
}
