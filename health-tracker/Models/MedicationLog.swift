//
//  MedicationLog.swift
//  health-tracker
//

import SwiftUI

/// What actually happened for a dose.
enum DoseStatus: String, CaseIterable, Identifiable {
    case taken
    case partial
    case skipped
    case extra

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taken: "Taken"
        case .partial: "Partial"
        case .skipped: "Skipped"
        case .extra: "Extra dose"
        }
    }

    var symbol: String {
        switch self {
        case .taken: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .skipped: "xmark.circle.fill"
        case .extra: "plus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .taken: .green
        case .partial: .orange
        case .skipped: .red
        case .extra: .blue
        }
    }
}

/// A record of a medication the user actually took (or skipped).
struct MedicationLog: Identifiable, Hashable {
    let id: UUID
    var medicationID: Medication.ID
    /// The scheduled slot this log satisfies, if any (nil for unscheduled/extra doses).
    var scheduledTime: TimeOfDay?
    /// The day of the scheduled slot. Stored separately from `takenAt` so a dose taken
    /// late (e.g. yesterday's 11 PM dose at 12:30 AM) still counts for the right day.
    var scheduledDay: Date
    var takenAt: Date
    /// The amount the user really took, which may differ from the prescribed dosage.
    var amountTaken: Double
    var unit: String
    var status: DoseStatus
    var note: String
    /// The user confirmed logging this dose despite an as-needed limit warning.
    var confirmedOverLimit: Bool

    /// The full scheduled date and time, if this dose was scheduled.
    var scheduledDate: Date? {
        scheduledTime?.date(on: scheduledDay)
    }

    init(
        id: UUID = UUID(),
        medicationID: Medication.ID,
        scheduledTime: TimeOfDay?,
        scheduledDay: Date? = nil,
        takenAt: Date = .now,
        amountTaken: Double,
        unit: String,
        status: DoseStatus,
        note: String = "",
        confirmedOverLimit: Bool = false
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduledTime = scheduledTime
        self.scheduledDay = Calendar.current.startOfDay(for: scheduledDay ?? takenAt)
        self.takenAt = takenAt
        self.amountTaken = amountTaken
        self.unit = unit
        self.status = status
        self.note = note
        self.confirmedOverLimit = confirmedOverLimit
    }
}
