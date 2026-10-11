//
//  RemindersScheduleView.swift
//  health-tracker
//
//  Variant C — merged daily schedule grouped by part of day, with a filter and an "add" sheet.
//

import SwiftUI

struct RemindersScheduleView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case medications = "Medications"
        case measurements = "Measurements"
        var id: String { rawValue }
    }

    private enum PartOfDay: String, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"

        init(_ time: TimeOfDay) {
            switch time.hour {
            case ..<12: self = .morning
            case 12..<17: self = .afternoon
            default: self = .evening
            }
        }
    }

    @Environment(HealthStore.self) private var store

    @State private var filter: Filter = .all
    @State private var isAdding = false

    private var items: [ScheduleItem] {
        store.dailySchedule().filter { item in
            switch (filter, item.kind) {
            case (.all, _), (.medications, .medication), (.measurements, .measurement): true
            default: false
            }
        }
    }

    var body: some View {
        let items = items

        NavigationStack {
            // Sections are written out statically: generating them from a ForEach
            // crashed the Xcode preview renderer.
            List {
                section(.morning, items: items)
                section(.afternoon, items: items)
                section(.evening, items: items)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No Reminders", systemImage: "bell.slash",
                                           description: Text("Import medications or add a measurement reminder."))
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Daily Schedule")
            .toolbar {
                Button("Add Reminder", systemImage: "plus") { isAdding = true }
            }
            .sheet(isPresented: $isAdding) {
                AddMeasurementReminderSheet()
                    .presentationDetents([.medium])
            }
            .reschedulesReminders(in: store)
        }
    }

    @ViewBuilder
    private func section(_ part: PartOfDay, items: [ScheduleItem]) -> some View {
        let group = items.filter { PartOfDay($0.time) == part }
        if !group.isEmpty {
            Section(part.rawValue) {
                ForEach(group) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: ScheduleItem) -> some View {
        HStack(spacing: 12) {
            Text(item.time.displayText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 76, alignment: .leading)
            Image(systemName: item.symbol)
                .foregroundStyle(item.color)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(item.title)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension ScheduleItem {
    var symbol: String {
        switch kind {
        case .medication: "pills.fill"
        case .measurement(let kind): kind.symbol
        }
    }

    var color: Color {
        switch kind {
        case .medication: .accentColor
        case .measurement(let kind): kind.color
        }
    }

    var title: String {
        switch kind {
        case .medication(let med): med.name
        case .measurement(let kind): kind.label
        }
    }

    var subtitle: String {
        switch kind {
        case .medication(let med): med.displayDosage
        case .measurement: "Take a reading"
        }
    }
}

/// Small sheet for adding a time to a measurement reminder.
private struct AddMeasurementReminderSheet: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MeasurementKind = .bloodPressure
    @State private var time = TimeOfDay(hour: 8, minute: 0)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Measurement", selection: $kind) {
                    ForEach(MeasurementKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                DatePicker("Time", selection: $time.asDate, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        add()
                        dismiss()
                    }
                }
            }
        }
    }

    private func add() {
        if let index = store.measurementReminders.firstIndex(where: { $0.kind == kind }) {
            if !store.measurementReminders[index].times.contains(time) {
                store.measurementReminders[index].times.append(time)
                store.measurementReminders[index].times.sort()
            }
            store.measurementReminders[index].isEnabled = true
        } else {
            store.measurementReminders.append(MeasurementReminder(kind: kind, times: [time], isEnabled: true))
        }
    }
}

#Preview("Reminders – Schedule") {
    RemindersScheduleView()
        .environment(HealthStore.preview)
}
