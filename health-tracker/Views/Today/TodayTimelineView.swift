//
//  TodayTimelineView.swift
//  health-tracker
//
//  A single chronological timeline mixing doses, measurements and symptoms,
//  with a "now" marker.
//

import SwiftUI

/// One row in the timeline.
private enum TimelineEntry: Identifiable {
    case dose(DoseSlot)
    /// A dose logged outside the schedule via the "+" button.
    case extraDose(Medication, MedicationLog)
    case measurement(MeasurementSlot)
    /// A reading recorded outside the reminder schedule via the "+" button.
    case extraMeasurement(MeasurementLog)
    case symptom(SymptomLog)

    var id: String {
        switch self {
        case .dose(let slot): "dose-\(slot.id)"
        case .extraDose(_, let log): "extra-\(log.id)"
        case .measurement(let slot): "measure-\(slot.id)"
        case .extraMeasurement(let log): "extra-measure-\(log.id)"
        case .symptom(let log): "symptom-\(log.id)"
        }
    }

    var date: Date {
        switch self {
        case .dose(let slot): slot.log?.takenAt ?? slot.date
        case .extraDose(_, let log): log.takenAt
        case .measurement(let slot): slot.log?.takenAt ?? slot.date
        case .extraMeasurement(let log): log.takenAt
        case .symptom(let log): log.date
        }
    }
}

/// Which kinds of entries the timeline shows. Stored as a String so it can be persisted.
enum TimelineFilter: String, CaseIterable, Identifiable {
    case all, medications, measurements, symptoms

    var id: String { rawValue }

    /// Short title that fits a four-segment control on iPhone.
    var shortLabel: String {
        switch self {
        case .all: "All"
        case .medications: "Meds"
        case .measurements: "Readings"
        case .symptoms: "Symptoms"
        }
    }

    var label: String {
        switch self {
        case .all: "All"
        case .medications: "Medications"
        case .measurements: "Measurements"
        case .symptoms: "Symptoms"
        }
    }

    func includes(_ category: TimelineFilter) -> Bool {
        self == .all || self == category
    }
}

/// Which measurement sheet to open, and for which reminder slot (if any).
private struct MeasurementRequest: Identifiable {
    let kind: MeasurementKind
    let scheduledTime: TimeOfDay?

    var id: String { "\(kind.rawValue)-\(scheduledTime?.id ?? -1)" }
}

struct TodayTimelineView: View {
    @Environment(HealthStore.self) private var store

    @State private var doseToLog: DoseSlot?
    @State private var extraDoseMedication: Medication?
    @State private var doseToShow: MedicationLog?
    @State private var measurementToRecord: MeasurementRequest?
    @State private var symptomToLog: SymptomType?
    /// The day being shown; today by default, can go back to earlier days.
    @State private var selectedDay: Date
    /// Updated every minute so the "now" line and due/overdue labels stay current.
    @State private var now = Date.now
    /// Remembered across launches.
    @AppStorage("timelineFilter") private var filter: TimelineFilter = .all

    private let formatter = PrescriptionFormatter()

    init(day: Date = .now) {
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    private var entries: [TimelineEntry] {
        var entries: [TimelineEntry] = []
        if filter.includes(.medications) {
            entries += store.doses(on: selectedDay).map(TimelineEntry.dose)
                + store.extraDoses(on: selectedDay).map(TimelineEntry.extraDose)
        }
        if filter.includes(.measurements) {
            entries += store.measurementSlots(on: selectedDay).map(TimelineEntry.measurement)
                + store.unscheduledMeasurements(on: selectedDay).map(TimelineEntry.extraMeasurement)
        }
        if filter.includes(.symptoms) {
            entries += store.symptoms(on: selectedDay).map(TimelineEntry.symptom)
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Empty-state text for the current day and filter.
    private var emptyDescription: String {
        switch filter {
        case .all:
            isToday
                ? "Import your medication list from the Import tab, or turn on measurement reminders."
                : "No doses, readings, or symptoms on this day."
        case .medications: "No doses scheduled or logged on this day."
        case .measurements: "No readings scheduled or recorded on this day."
        case .symptoms: "No symptoms logged on this day."
        }
    }

    var body: some View {
        let entries = entries
        // Index of the first entry after "now", where the marker is drawn (today only).
        let nowIndex = isToday ? (entries.firstIndex { $0.date > now } ?? entries.count) : nil

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == nowIndex {
                            nowMarker
                        }
                        // Dim only earlier entries of today; past days are shown normally.
                        row(for: entry, isPast: isToday && entry.date <= now)
                    }
                    if nowIndex == entries.count {
                        nowMarker
                    }
                }
                .padding()
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        isToday ? "Nothing Scheduled" : "Nothing Recorded",
                        systemImage: isToday ? "calendar.badge.clock" : "calendar",
                        description: Text(emptyDescription)
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    dayNavigator
                    Picker("Show", selection: $filter) {
                        ForEach(TimelineFilter.allCases) { option in
                            Text(option.shortLabel)
                                .accessibilityLabel(option.label)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
            .task {
                // Tick at the start of each minute while the timeline is visible.
                while !Task.isCancelled {
                    let seconds = 60 - Calendar.current.component(.second, from: .now)
                    try? await Task.sleep(for: .seconds(seconds))
                    now = .now
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                // Pick a symptom from the dropdown, then fill in the details.
                Menu("Log Symptom", systemImage: "stethoscope") {
                    ForEach(SymptomType.allCases) { type in
                        Button(type.label, systemImage: type.symbol) {
                            symptomToLog = type
                        }
                    }
                }
                // Record a reading on demand, without needing a reminder.
                Menu("Record Measurement", systemImage: "gauge.with.dots.needle.33percent") {
                    ForEach(MeasurementKind.allCases) { kind in
                        Button(kind.label, systemImage: kind.symbol) {
                            measurementToRecord = MeasurementRequest(kind: kind, scheduledTime: nil)
                        }
                    }
                }
                // Log an extra dose, or a scheduled dose taken at a different time.
                Menu("Log Medication", systemImage: "pill.fill") {
                    if store.medications.isEmpty {
                        Text("Import your medications first")
                    }
                    ForEach(store.medications) { med in
                        Button("\(med.name) (\(formatter.doseText(for: med)))", systemImage: "pills") {
                            extraDoseMedication = med
                        }
                    }
                }
            }
            .sheet(item: $doseToLog) { slot in
                LogMedicationView(medication: slot.medication, scheduledTime: slot.time, day: selectedDay)
            }
            .sheet(item: $extraDoseMedication) { med in
                LogMedicationView(medication: med, day: selectedDay)
            }
            .sheet(item: $doseToShow) { log in
                if let medication = store.medication(for: log.medicationID) {
                    DoseDetailView(medication: medication, log: log)
                }
            }
            .sheet(item: $measurementToRecord) { request in
                LogMeasurementView(kind: request.kind, scheduledTime: request.scheduledTime, day: selectedDay)
            }
            .sheet(item: $symptomToLog) { type in
                LogSymptomView(type: type, day: selectedDay)
            }
        }
    }

    /// "‹  Sun, Oct 11  ›" bar for moving between days; can't go past today.
    private var dayNavigator: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return HStack {
            Button("Previous Day", systemImage: "chevron.left") {
                selectedDay = calendar.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)

            Spacer()

            DatePicker(
                "Day",
                selection: Binding(
                    get: { selectedDay },
                    set: { selectedDay = calendar.startOfDay(for: $0) }
                ),
                in: ...today,
                displayedComponents: .date
            )
            .labelsHidden()

            if !isToday {
                Button("Today") { selectedDay = today }
                    .buttonStyle(.glass)
            }

            Spacer()

            Button("Next Day", systemImage: "chevron.right") {
                selectedDay = min(calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? today, today)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .disabled(isToday)
        }
        .padding(.horizontal)
    }

    private var nowMarker: some View {
        HStack(spacing: 8) {
            Text(now, style: .time)
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
                .frame(width: 64, alignment: .trailing)
            Circle().fill(.red).frame(width: 10, height: 10)
            Rectangle().fill(.red).frame(height: 2)
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Now")
    }

    @ViewBuilder
    private func row(for entry: TimelineEntry, isPast: Bool) -> some View {
        switch entry {
        case .dose(let slot):
            if let log = slot.log {
                // Logged dose: tap to see schedule, timing, amount and note.
                Button { doseToShow = log } label: {
                    timelineRow(
                        date: entry.date, icon: log.status.symbol, color: log.status.color,
                        title: slot.medication.name,
                        subtitle: doseSubtitle(log, medication: slot.medication),
                        isPast: isPast
                    ) { detailChevron }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows dose details")
            } else {
                timelineRow(
                    date: entry.date,
                    icon: "pills.fill",
                    color: slot.isOverdue(now: now) ? .red : .accentColor,
                    title: slot.medication.name,
                    subtitle: "\(formatter.subtitle(for: slot.medication, on: selectedDay)) · \(pendingLabel(for: slot.date))",
                    isPast: isPast
                ) {
                    Button("Log") { doseToLog = slot }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        case .extraDose(let medication, let log):
            Button { doseToShow = log } label: {
                timelineRow(
                    date: entry.date, icon: log.status.symbol, color: log.status.color,
                    title: medication.name,
                    subtitle: doseSubtitle(log, medication: medication),
                    isPast: isPast
                ) { detailChevron }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows dose details")
        case .measurement(let slot):
            if let log = slot.log {
                timelineRow(
                    date: entry.date, icon: slot.kind.symbol, color: slot.kind.color,
                    title: slot.kind.label, subtitle: measurementSubtitle(log), isPast: isPast
                ) { EmptyView() }
            } else {
                timelineRow(
                    date: entry.date, icon: slot.kind.symbol, color: slot.kind.color,
                    title: slot.kind.label, subtitle: "Reading \(pendingLabel(for: slot.date))", isPast: isPast
                ) {
                    Button("Record") {
                        measurementToRecord = MeasurementRequest(kind: slot.kind, scheduledTime: slot.time)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
        case .extraMeasurement(let log):
            timelineRow(
                date: entry.date, icon: log.kind.symbol, color: log.kind.color,
                title: log.kind.label, subtitle: measurementSubtitle(log), isPast: isPast
            ) { EmptyView() }
        case .symptom(let log):
            timelineRow(
                date: entry.date, icon: log.type.symbol, color: log.severity.color,
                title: log.displayName, subtitle: log.note.isEmpty ? log.severity.label : log.note,
                isPast: isPast
            ) { SeverityBadge(severity: log.severity) }
        }
    }

    /// "due" (upcoming), "overdue" (earlier today) or "missed" (a past day).
    private func pendingLabel(for date: Date) -> String {
        if date > now { return "due" }
        return isToday ? "overdue" : "missed"
    }

    private var detailChevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
    }

    /// e.g. "Partial · ½ tablet (250 mg) · has note".
    private func doseSubtitle(_ log: MedicationLog, medication: Medication) -> String {
        var parts = [log.status.label]
        if log.status != .skipped {
            parts.append(formatter.doseText(for: medication, quantity: log.quantityTaken))
        }
        if log.confirmedOverLimit { parts.append("over limit") }
        if !log.note.isEmpty { parts.append("has note") }
        return parts.joined(separator: " · ")
    }

    /// e.g. "128/84 mmHg · Left arm, seated."
    private func measurementSubtitle(_ log: MeasurementLog) -> String {
        log.note.isEmpty ? log.displayValue : "\(log.displayValue) · \(log.note)"
    }

    private func timelineRow<Accessory: View>(
        date: Date,
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isPast: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(date, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, 8)

            // Connector line with a dot for this entry.
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color, in: .circle)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 26)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                accessory()
            }
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
        // Makes the whole row tappable when wrapped in a Button.
        .contentShape(.rect)
        .opacity(isPast ? 0.7 : 1)
    }
}

#Preview("Today – Timeline") {
    TodayTimelineView()
        .environment(HealthStore.preview)
}

#Preview("Today – Timeline (Yesterday)") {
    TodayTimelineView(day: SampleData.yesterday)
        .environment(HealthStore.preview)
}

#Preview("Today – Timeline (Empty)") {
    TodayTimelineView()
        .environment(HealthStore())
}
