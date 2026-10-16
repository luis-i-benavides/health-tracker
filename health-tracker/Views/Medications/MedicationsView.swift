//
//  MedicationsView.swift
//  health-tracker
//
//  The medication list: add, edit and delete medications, and ask Claude to optimize
//  when doses are taken.
//

import SwiftUI

struct MedicationsView: View {
    @Environment(HealthStore.self) private var store

    @State private var medicationToEdit: Medication?
    @State private var isAdding = false
    @State private var isOptimizing = false
    @State private var pendingDeletion: Medication?

    private let formatter = PrescriptionFormatter()

    private var scheduled: [Medication] { store.medications.filter { !$0.schedule.isAsNeeded } }
    private var asNeeded: [Medication] { store.medications.filter(\.schedule.isAsNeeded) }

    var body: some View {
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
                        Text("Add a medication, or import your list from the Import tab.")
                    } actions: {
                        Button("Add Medication") { isAdding = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                Button("Add Medication", systemImage: "plus") { isAdding = true }
            }
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

    private func delete(_ medication: Medication) {
        store.deleteMedication(id: medication.id)
        Task { await store.rescheduleNotifications() }
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
