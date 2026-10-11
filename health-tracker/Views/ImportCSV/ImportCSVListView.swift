//
//  ImportCSVListView.swift
//  health-tracker
//
//  Variant A — List with format help, parsed rows, and an errors section.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVListView: View {
    @Environment(HealthStore.self) private var store

    @State private var isPickingFile = false
    @State private var result: CSVParseResult?
    @State private var readError: String?
    @State private var didImport = false

    /// Lets previews show an already-parsed file.
    init(result: CSVParseResult? = nil) {
        _result = State(initialValue: result)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("CSV Format") {
                    CSVFormatHelp()
                }

                Section {
                    Button("Choose CSV File…", systemImage: "doc.badge.plus") {
                        isPickingFile = true
                    }
                    if let readError {
                        Text(readError).foregroundStyle(.red)
                    }
                }

                if let result {
                    Section("Ready to import (\(result.medications.count))") {
                        ForEach(result.medications) { med in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name).font(.headline)
                                Text("\(med.displayDosage) at \(med.times.map(\.displayText).formatted(.list(type: .and)))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !result.errors.isEmpty {
                        Section("Skipped rows (\(result.errors.count))") {
                            CSVErrorList(errors: result.errors)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                await store.applyImport(result.medications)
                                didImport = true
                            }
                        } label: {
                            Text("Replace Medication List")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(result.medications.isEmpty)
                    } footer: {
                        Text("Your current \(store.medications.count) medications will be replaced and dose reminders rescheduled.")
                    }
                }
            }
            .navigationTitle("Import Medications")
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { outcome in
                handle(outcome)
            }
            .alert("Medications Imported", isPresented: $didImport) {
                Button("OK", role: .cancel) { result = nil }
            } message: {
                Text(store.lastSchedulingError ?? "Reminders are scheduled for every dose.")
            }
        }
    }

    private func handle(_ outcome: Result<URL, any Error>) {
        do {
            result = try store.readCSV(from: outcome.get())
            readError = nil
        } catch {
            result = nil
            readError = "Couldn't read the file: \(error.localizedDescription)"
        }
    }
}

#Preview("Import CSV – List") {
    ImportCSVListView(result: CSVMedicationParser.parse(SampleData.csv))
        .environment(HealthStore.preview)
}
