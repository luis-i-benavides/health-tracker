//
//  ImportCSVCardView.swift
//  health-tracker
//
//  Variant B — big "drop zone" style upload card and preview cards per medication.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVCardView: View {
    @Environment(HealthStore.self) private var store

    @State private var isPickingFile = false
    @State private var result: CSVParseResult?
    @State private var readError: String?
    @State private var isImporting = false
    @State private var showFormat = false

    init(result: CSVParseResult? = nil) {
        _result = State(initialValue: result)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    uploadCard

                    if let result {
                        if !result.errors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(result.errors.count) rows need attention")
                                    .font(.headline)
                                CSVErrorList(errors: result.errors)
                            }
                            .cardStyle()
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.orange.opacity(0.5)))
                        }

                        ForEach(result.medications) { med in
                            medicationCard(med)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import")
            .toolbar {
                Button("Format", systemImage: "questionmark.circle") { showFormat = true }
            }
            .sheet(isPresented: $showFormat) {
                NavigationStack {
                    CSVFormatHelp()
                        .padding()
                        .navigationTitle("CSV Format")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
            .safeAreaInset(edge: .bottom) {
                if let result, !result.medications.isEmpty {
                    Button {
                        isImporting = true
                        Task {
                            await store.applyImport(result.medications)
                            isImporting = false
                            self.result = nil
                        }
                    } label: {
                        Label("Import \(result.medications.count) Medications", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isImporting)
                    .padding()
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { outcome in
                do {
                    result = try store.readCSV(from: outcome.get())
                    readError = nil
                } catch {
                    readError = "Couldn't read the file: \(error.localizedDescription)"
                }
            }
        }
    }

    private var uploadCard: some View {
        Button {
            isPickingFile = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: result == nil ? "arrow.up.doc" : "doc.text.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text(result == nil ? "Upload your medication list" : "Choose a different file")
                    .font(.headline)
                Text("CSV with name, dosage, unit, times")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let readError {
                    Text(readError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(.background, in: .rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.tint.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
        }
        .buttonStyle(.plain)
    }

    private func medicationCard(_ med: Medication) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "pills.fill")
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.tint, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(med.name).font(.headline)
                Text(med.displayDosage)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(med.times) { time in
                        Text(time.displayText)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.12), in: .capsule)
                    }
                }
            }
        }
        .cardStyle()
    }
}

#Preview("Import CSV – Cards") {
    ImportCSVCardView(result: CSVMedicationParser.parse(SampleData.csv))
        .environment(HealthStore.preview)
}

#Preview("Import CSV – Cards (Empty)") {
    ImportCSVCardView()
        .environment(HealthStore.preview)
}
