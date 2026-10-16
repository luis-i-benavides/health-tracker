//
//  SharedComponents.swift
//  health-tracker
//
//  Small building blocks reused across the layout variants.
//

import SwiftUI
import UserNotifications

extension Binding {
    /// Runs `action` whenever the binding is written, e.g. to note that the user edited a value.
    func onSet(_ action: @escaping () -> Void) -> Binding {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action() })
    }
}

extension Date {
    /// The time to record for a log entry. When logging for today without touching the time
    /// picker, that's the moment Save is tapped (not when the sheet opened); otherwise the chosen time.
    static func logTime(chosen: Date, edited: Bool, day: Date, calendar: Calendar = .current) -> Date {
        !edited && calendar.isDateInToday(day) ? .now : chosen
    }
}

extension String {
    /// First letter uppercased, for phrases shown on their own ("twice daily…" → "Twice daily…").
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}

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
    @State private var nextReminder: (title: String, date: Date)?
    @State private var testSent = false

    var body: some View {
        Group {
            switch status {
            case .authorized, .provisional, .ephemeral:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications are on", systemImage: "bell.badge.fill")
                        .foregroundStyle(.green)
                    if let nextReminder {
                        Text("Next: \(nextReminder.title) at \(nextReminder.date.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No reminders scheduled yet.")
                            .foregroundStyle(.secondary)
                    }
                    Button(testSent ? "Test Sent — Arrives in 5 Seconds" : "Send Test Notification",
                           systemImage: "paperplane") {
                        Task {
                            try? await NotificationScheduler().sendTestNotification()
                            testSent = true
                            try? await Task.sleep(for: .seconds(6))
                            testSent = false
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(testSent)
                }
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
        // Refresh after every reschedule so "Next:" reflects the current reminders.
        .task(id: store.scheduleVersion) {
            let scheduler = NotificationScheduler()
            status = await scheduler.authorizationStatus()
            nextReminder = await scheduler.pendingReminders()
                .first { $0.next != nil }
                .map { ($0.title, $0.next!) }
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

/// Centered green Save button pinned to the bottom of the logging dialogs.
/// (The dialogs have no Cancel button: tap outside the sheet or swipe it down to dismiss.)
struct DialogSaveButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: 240)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(.green)
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// Form section with a Delete button for edit dialogs; asks for confirmation first.
struct DeleteEntrySection: View {
    /// e.g. "Dose", "Reading", "Symptom".
    let entryName: String
    /// Extra detail for the confirmation, e.g. what happens to a scheduled slot.
    var message: String = "This can't be undone."
    let onDelete: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Section {
            Button("Delete \(entryName)", systemImage: "trash", role: .destructive) {
                isConfirming = true
            }
            // Otherwise the icon takes the accent color while the title is red.
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .confirmationDialog("Delete this \(entryName.lowercased())?", isPresented: $isConfirming,
                                titleVisibility: .visible) {
                Button("Delete \(entryName)", role: .destructive, action: onDelete)
            } message: {
                Text(message)
            }
        }
    }
}

/// The expected CSV layout, shown on import screens.
struct CSVFormatHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
            name,strength,form,quantity,frequency,food,duration_days
            Metformin,500 mg,tablet,1,twice daily,with food,
            Amoxicillin,500 mg,capsule,1,TID,with food,10
            """)
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))

            Text("One row per medication; columns can be in any order. Required: name, strength, frequency. Optional: generic, form, quantity, route, times (24-hour HH:mm, separated by “;”), food, duration_days, start, purpose, and for as-needed medications max_per_24h and min_hours_apart. The older name,dosage,unit,times format also works.")
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
