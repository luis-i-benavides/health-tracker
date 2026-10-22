//
//  MedicationsView.swift
//  health-tracker
//
//  The medication list: add, edit and delete medications, ask Claude to optimize
//  when doses are taken, and export or import the schedule as a file.
//

import SwiftUI
import UniformTypeIdentifiers

struct MedicationsView: View {
    @Environment(HealthStore.self) private var store

    @State private var medicationToEdit: Medication?
    @State private var isAdding = false
    @State private var isOptimizing = false
    @State private var pendingDeletion: Medication?
    /// The schedule being saved to Files; set while the exporter is showing.
    @State private var scheduleToExport: ScheduleExportFile?
    @State private var isPickingImport = false
    /// A schedule read from a file, waiting for the user to confirm replacing theirs.
    @State private var pendingImport: ScheduleExport?
    @State private var transferError: String?

    private let formatter = PrescriptionFormatter()

    private var scheduled: [Medication] { store.medications.filter { !$0.schedule.isAsNeeded } }
    private var asNeeded: [Medication] { store.medications.filter(\.schedule.isAsNeeded) }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            List {
                if !store.medications.isEmpty {
                    Section {
                        Button {
                            isOptimizing = true
                        } label: {
                            // An HStack rather than a Label: in a List, Label reserves a
                            // leading icon column, which pushed the title off center.
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Optimize Schedule")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("Claude suggests when to take each dose: fewer times a day, with-food doses at meals, and protection against nausea. You review the changes before anything is updated.")
                    }
                }

                if !store.medications.isEmpty {
                    DailyRoutineSection(mealTimes: $store.mealTimes)
                    SchedulePreferencesSection(preferences: $store.schedulePreferences)
                }

                if !scheduled.isEmpty {
                    Section("Scheduled") {
                        ForEach(scheduled) { row(for: $0) }
                    }
                }
                if !asNeeded.isEmpty {
                    Section("As Needed") {
                        ForEach(asNeeded) { row(for: $0) }
                    }
                }
            }
            .overlay {
                if store.medications.isEmpty {
                    ContentUnavailableView {
                        Label("No Medications", systemImage: "pills")
                    } description: {
                        Text("Add a medication, or import an exported schedule from the ⋯ menu.")
                    } actions: {
                        Button("Add Medication") { isAdding = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                Menu("More", systemImage: "ellipsis") {
                    Button("Export Schedule…", systemImage: "square.and.arrow.up") {
                        do {
                            scheduleToExport = try ScheduleExportFile(store.scheduleExport())
                        } catch {
                            transferError = "Couldn't export the schedule: \(error.localizedDescription)"
                        }
                    }
                    .disabled(store.medications.isEmpty)
                    Button("Import Schedule…", systemImage: "square.and.arrow.down") {
                        isPickingImport = true
                    }
                }
                Button("Add Medication", systemImage: "plus") { isAdding = true }
            }
            .modifier(scheduleTransfer)
            .sheet(isPresented: $isAdding) {
                EditMedicationView(medication: nil)
            }
            .sheet(item: $medicationToEdit) { medication in
                EditMedicationView(medication: medication)
            }
            .sheet(isPresented: $isOptimizing) {
                OptimizeScheduleView()
            }
            .confirmationDialog(
                "Delete \(pendingDeletion?.name ?? "medication")?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { medication in
                Button("Delete Medication", role: .destructive) { delete(medication) }
            } message: { medication in
                Text(EditMedicationView.deletionMessage(for: medication, in: store))
            }
        }
    }

    private func row(for medication: Medication) -> some View {
        Button { medicationToEdit = medication } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatter.title(for: medication))
                    .font(.headline)
                Text(formatter.instruction(for: medication))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this medication")
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = medication }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { medicationToEdit = medication }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = medication }
        }
    }

    private var scheduleTransfer: ScheduleTransferModifier {
        ScheduleTransferModifier(
            store: store,
            scheduleToExport: $scheduleToExport,
            isPickingImport: $isPickingImport,
            pendingImport: $pendingImport,
            transferError: $transferError
        )
    }

    private func delete(_ medication: Medication) {
        store.deleteMedication(id: medication.id)
        Task { await store.rescheduleNotifications() }
    }
}

/// The Files exporter and importer for the schedule, the confirmation before an import
/// replaces the current schedule, and the error alert. Kept out of `MedicationsView.body`
/// so the compiler can type-check it.
private struct ScheduleTransferModifier: ViewModifier {
    let store: HealthStore
    @Binding var scheduleToExport: ScheduleExportFile?
    @Binding var isPickingImport: Bool
    @Binding var pendingImport: ScheduleExport?
    @Binding var transferError: String?

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: Binding(
                    get: { scheduleToExport != nil },
                    set: { if !$0 { scheduleToExport = nil } }
                ),
                item: scheduleToExport,
                contentTypes: [.json],
                defaultFilename: scheduleToExport?.filename
            ) { result in
                if case .failure(let error) = result {
                    transferError = "Couldn't export the schedule: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $isPickingImport, allowedContentTypes: [.json]) { result in
                do {
                    pendingImport = try ScheduleExport.read(from: result.get())
                } catch {
                    transferError = error.localizedDescription
                }
            }
            .alert(
                "Replace Your Schedule?",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { if !$0 { pendingImport = nil } }
                ),
                presenting: pendingImport
            ) { export in
                Button("Replace", role: .destructive) {
                    store.applyScheduleImport(export)
                    Task { await store.rescheduleNotifications() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { export in
                Text(importMessage(for: export))
            }
            .alert(
                "Import or Export Failed",
                isPresented: Binding(
                    get: { transferError != nil },
                    set: { if !$0 { transferError = nil } }
                ),
                presenting: transferError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    /// e.g. "The file from Oct 21, 2026 has 5 medications. They'll replace your 4 medications, …"
    private func importMessage(for export: ScheduleExport) -> String {
        let date = export.exportedAt.formatted(date: .abbreviated, time: .omitted)
        let count = export.medications.count
        let current = store.medications.count
        return "The file from \(date) has \(count) medication\(count == 1 ? "" : "s"). They'll replace your \(current) medication\(current == 1 ? "" : "s"), daily routine, schedule preferences and reminders. Doses already logged for medications with the same name are kept."
    }
}

#Preview("Medications") {
    MedicationsView()
        .environment(HealthStore.preview)
}

#Preview("Medications – Empty") {
    MedicationsView()
        .environment(HealthStore())
}
