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
    var title: LocalizedStringKey = "Save"
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
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
