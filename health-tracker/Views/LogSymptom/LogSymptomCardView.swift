//
//  LogSymptomCardView.swift
//  health-tracker
//
//  Variant B — card layout with a prominent dropdown and colored severity chips.
//

import SwiftUI

struct LogSymptomCardView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var type: SymptomType = .headache
    @State private var customName = ""
    @State private var severity: Severity = .moderate
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Symptom dropdown card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What are you feeling?")
                            .font(.headline)
                        Menu {
                            Picker("Symptom", selection: $type) {
                                ForEach(SymptomType.allCases) { type in
                                    Label(type.label, systemImage: type.symbol).tag(type)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: type.symbol)
                                    .font(.title2)
                                    .frame(width: 36)
                                Text(type.label)
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if type == .other {
                            TextField("Describe the symptom", text: $customName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .cardStyle()

                    // Severity chips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How bad is it?")
                            .font(.headline)
                        HStack(spacing: 10) {
                            ForEach(Severity.allCases) { level in
                                let isSelected = level == severity
                                Button {
                                    severity = level
                                } label: {
                                    VStack(spacing: 6) {
                                        HStack(spacing: 3) {
                                            ForEach(1...3, id: \.self) { dot in
                                                Circle()
                                                    .frame(width: 8, height: 8)
                                                    .opacity(dot <= level.rawValue ? 1 : 0.25)
                                            }
                                        }
                                        Text(level.label)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .foregroundStyle(isSelected ? .white : level.color)
                                    .background(isSelected ? level.color : level.color.opacity(0.12),
                                                in: .rect(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .cardStyle()

                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.headline)
                        TextField("Triggers, duration, what helped…", text: $note, axis: .vertical)
                            .lineLimit(4...8)
                    }
                    .cardStyle()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Symptom")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.logSymptom(SymptomLog(type: type, customName: customName, severity: severity, note: note))
                    dismiss()
                } label: {
                    Text("Save Symptom")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(severity.color)
                .disabled(type == .other && customName.isEmpty)
                .padding()
            }
        }
    }
}

#Preview("Log Symptom – Cards") {
    LogSymptomCardView()
        .environment(HealthStore.preview)
}
