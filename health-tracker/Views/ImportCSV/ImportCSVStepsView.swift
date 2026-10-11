//
//  ImportCSVStepsView.swift
//  health-tracker
//
//  Variant C — guided three-step flow: learn the format → choose a file → review & confirm.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVStepsView: View {
    private enum Step: Int, CaseIterable {
        case format, choose, review

        var title: String {
            switch self {
            case .format: "Format"
            case .choose: "Choose"
            case .review: "Review"
            }
        }
    }

    @Environment(HealthStore.self) private var store

    @State private var step: Step
    @State private var isPickingFile = false
    @State private var result: CSVParseResult?
    @State private var readError: String?
    @State private var isDone = false

    init(result: CSVParseResult? = nil) {
        _result = State(initialValue: result)
        _step = State(initialValue: result == nil ? .format : .review)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                    .padding()

                Group {
                    switch step {
                    case .format: formatStep
                    case .choose: chooseStep
                    case .review: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.default, value: step)
            }
            .navigationTitle("Import Medications")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { outcome in
                do {
                    result = try store.readCSV(from: outcome.get())
                    readError = nil
                    step = .review
                } catch {
                    readError = "Couldn't read the file: \(error.localizedDescription)"
                }
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.self) { item in
                let isReached = item.rawValue <= step.rawValue
                VStack(spacing: 6) {
                    Text("\(item.rawValue + 1)")
                        .font(.subheadline.bold())
                        .foregroundStyle(isReached ? .white : .secondary)
                        .frame(width: 30, height: 30)
                        .background(isReached ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .circle)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(isReached ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityValue(item == step ? "Current step" : "")
            }
        }
    }

    private var formatStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prepare your file")
                .font(.title2.bold())
            Text("Export from a spreadsheet as CSV with these four columns:")
                .foregroundStyle(.secondary)
            CSVFormatHelp()
            Spacer()
            Button {
                step = .choose
            } label: {
                Text("Next").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var chooseStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Choose your CSV file")
                .font(.title2.bold())
            Text("From Files, iCloud Drive, or another provider.")
                .foregroundStyle(.secondary)
            if let readError {
                Text(readError).foregroundStyle(.red).font(.footnote)
            }
            Spacer()
            HStack {
                Button("Back") { step = .format }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button {
                    isPickingFile = true
                } label: {
                    Text("Browse…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var reviewStep: some View {
        if let result {
            VStack(spacing: 0) {
                List {
                    Section {
                        LabeledContent("Medications found", value: "\(result.medications.count)")
                        LabeledContent("Daily reminders", value: "\(result.medications.reduce(0) { $0 + $1.times.count })")
                        if !result.errors.isEmpty {
                            LabeledContent("Rows skipped", value: "\(result.errors.count)")
                                .foregroundStyle(.orange)
                        }
                    }
                    Section("Medications") {
                        ForEach(result.medications) { med in
                            LabeledContent(med.name) {
                                Text("\(med.displayDosage) · \(med.times.map(\.formatted24h).joined(separator: ", "))")
                            }
                        }
                    }
                    if !result.errors.isEmpty {
                        Section("Fix these rows and re-import") {
                            CSVErrorList(errors: result.errors)
                        }
                    }
                }

                HStack {
                    Button("Choose Another") { step = .choose }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    Button {
                        Task {
                            await store.applyImport(result.medications)
                            isDone = true
                        }
                    } label: {
                        Text(isDone ? "Imported ✓" : "Import").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(result.medications.isEmpty || isDone)
                }
                .padding()
            }
        }
    }
}

#Preview("Import CSV – Steps (Review)") {
    ImportCSVStepsView(result: CSVMedicationParser.parse(SampleData.csv))
        .environment(HealthStore.preview)
}

#Preview("Import CSV – Steps (Start)") {
    ImportCSVStepsView()
        .environment(HealthStore.preview)
}
