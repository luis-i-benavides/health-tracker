//
//  TodayTimelineView.swift
//  health-tracker
//
//  Variant C — a single chronological timeline mixing doses, measurements and symptoms,
//  with a "now" marker.
//

import SwiftUI

/// One row in the timeline.
private enum TimelineEntry: Identifiable {
    case dose(DoseSlot)
    case measurement(MeasurementKind, TimeOfDay)
    case symptom(SymptomLog)

    var id: String {
        switch self {
        case .dose(let slot): "dose-\(slot.id)"
        case .measurement(let kind, let time): "measure-\(kind.rawValue)-\(time.id)"
        case .symptom(let log): "symptom-\(log.id)"
        }
    }

    var date: Date {
        switch self {
        case .dose(let slot): slot.log?.takenAt ?? slot.time.date()
        case .measurement(_, let time): time.date()
        case .symptom(let log): log.date
        }
    }
}

struct TodayTimelineView: View {
    @Environment(HealthStore.self) private var store

    @State private var doseToLog: DoseSlot?
    @State private var isLoggingSymptom = false

    private var entries: [TimelineEntry] {
        let doses = store.todaysDoses().map(TimelineEntry.dose)
        let measurements = store.measurementReminders.filter(\.isEnabled).flatMap { reminder in
            reminder.times.map { TimelineEntry.measurement(reminder.kind, $0) }
        }
        let symptoms = store.todaysSymptoms().map(TimelineEntry.symptom)
        return (doses + measurements + symptoms).sorted { $0.date < $1.date }
    }

    var body: some View {
        let entries = entries
        let now = Date.now
        // Index of the first entry after "now", where the marker is drawn.
        let nowIndex = entries.firstIndex { $0.date > now } ?? entries.count

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == nowIndex {
                            nowMarker
                        }
                        row(for: entry, isPast: entry.date <= now)
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
                        "Nothing Scheduled",
                        systemImage: "calendar.badge.clock",
                        description: Text("Import your medication list from the Import tab, or turn on measurement reminders.")
                    )
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                Button("Log Symptom", systemImage: "stethoscope") { isLoggingSymptom = true }
            }
            .sheet(item: $doseToLog) { slot in
                LogMedicationQuickView(medication: slot.medication, scheduledTime: slot.time)
            }
            .sheet(isPresented: $isLoggingSymptom) {
                LogSymptomCompactView(isSheet: true)
            }
        }
    }

    private var nowMarker: some View {
        HStack(spacing: 8) {
            Text(Date.now, style: .time)
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
            timelineRow(
                date: entry.date,
                icon: slot.log?.status.symbol ?? "pills.fill",
                color: slot.log?.status.color ?? (slot.isOverdue() ? .red : .accentColor),
                title: slot.medication.name,
                subtitle: slot.log.map { "\($0.status.label) · \($0.amountTaken.formatted()) \($0.unit)" }
                    ?? "\(slot.medication.displayDosage) due",
                isPast: isPast
            ) {
                if slot.log == nil {
                    Button("Log") { doseToLog = slot }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        case .measurement(let kind, _):
            timelineRow(
                date: entry.date, icon: kind.symbol, color: kind.color,
                title: kind.label, subtitle: "Measurement reminder", isPast: isPast
            ) { EmptyView() }
        case .symptom(let log):
            timelineRow(
                date: entry.date, icon: log.type.symbol, color: log.severity.color,
                title: log.displayName, subtitle: log.note.isEmpty ? log.severity.label : log.note,
                isPast: isPast
            ) { SeverityBadge(severity: log.severity) }
        }
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
        .opacity(isPast ? 0.7 : 1)
    }
}

#Preview("Today – Timeline") {
    TodayTimelineView()
        .environment(HealthStore.preview)
}

#Preview("Today – Timeline (Empty)") {
    TodayTimelineView()
        .environment(HealthStore())
}
