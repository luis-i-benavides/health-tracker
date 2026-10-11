//
//  SharedComponents.swift
//  health-tracker
//
//  Small building blocks reused across the layout variants.
//

import SwiftUI
import UserNotifications

extension TimeOfDay {
    /// Locale-aware short time, e.g. "8:00 AM" or "08:00".
    var displayText: String {
        date().formatted(date: .omitted, time: .shortened)
    }
}

extension Binding where Value == TimeOfDay {
    /// Bridges a `TimeOfDay` to the `Date` that `DatePicker` expects.
    var asDate: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.date() },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                wrappedValue = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}

/// Shows whether notifications are allowed and offers to request permission.
struct NotificationPermissionBanner: View {
    @Environment(HealthStore.self) private var store
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Group {
            switch status {
            case .authorized, .provisional, .ephemeral:
                Label("Notifications are on", systemImage: "bell.badge.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Notifications are off. Turn them on in Settings › Health Tracker.", systemImage: "bell.slash.fill")
                    .foregroundStyle(.red)
            default:
                Button("Allow Notifications", systemImage: "bell") {
                    Task {
                        await store.rescheduleNotifications()
                        status = await NotificationScheduler().authorizationStatus()
                    }
                }
            }
        }
        .font(.subheadline)
        .task {
            status = await NotificationScheduler().authorizationStatus()
        }
    }
}

extension View {
    /// Reschedules notifications whenever reminder settings are edited.
    func reschedulesReminders(in store: HealthStore) -> some View {
        onChange(of: store.measurementReminders) {
            Task { await store.rescheduleNotifications() }
        }
        .onChange(of: store.medicationRemindersEnabled) {
            Task { await store.rescheduleNotifications() }
        }
    }

    /// Full-width rounded card used by the card-based layout variants.
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: .rect(cornerRadius: 20))
    }
}

/// A small colored capsule showing a symptom severity.
struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.15), in: .capsule)
    }
}

/// Icon + label for a dose's logged status, or a pending/overdue state.
struct DoseStatusLabel: View {
    let slot: DoseSlot

    var body: some View {
        if let log = slot.log {
            Label(log.status.label, systemImage: log.status.symbol)
                .foregroundStyle(log.status.color)
        } else if slot.isOverdue() {
            Label("Overdue", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        } else {
            Label("Upcoming", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }
}

/// The symptom dropdown, shared by every Log Symptom variant.
struct SymptomPicker: View {
    @Binding var selection: SymptomType

    var body: some View {
        Picker("Symptom", selection: $selection) {
            ForEach(SymptomType.allCases) { type in
                Label(type.label, systemImage: type.symbol).tag(type)
            }
        }
        .pickerStyle(.menu)
    }
}

/// The expected CSV layout, shown on import screens.
struct CSVFormatHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
            name,dosage,unit,times
            Lisinopril,10,mg,08:00
            Metformin,500,mg,08:00;20:00
            """)
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))

            Text("One row per medication. Separate multiple times with “;” and use 24-hour HH:mm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Lists import problems with their CSV line numbers.
struct CSVErrorList: View {
    let errors: [CSVParseError]

    var body: some View {
        ForEach(errors) { error in
            Label {
                Text("Line \(error.line): \(error.message)")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
