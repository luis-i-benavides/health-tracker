//
//  ScheduleTransfer.swift
//  health-tracker
//
//  Exports the medication list, daily routine, schedule preferences and reminder settings as
//  a JSON file, and reads one back — e.g. to move a schedule to another device or keep a
//  backup before optimizing. Logged history (doses, readings, symptoms) isn't included.
//
//  Compatibility: like `HealthSnapshot`, add new properties as optionals (or bump
//  `currentVersion`) so older exports keep importing.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The contents of an exported schedule file.
struct ScheduleExport: Codable, Equatable {
    static let currentVersion = 1

    var version = ScheduleExport.currentVersion
    var exportedAt: Date
    var medications: [Medication]
    var mealTimes: MealTimes
    var schedulePreferences: SchedulePreferences
    /// Medication reminders on or off. Added after the first exports; `nil` in those, and
    /// importing them leaves the current reminder settings alone.
    var medicationRemindersEnabled: Bool?
    /// Measurement reminders (times, on or off). `nil` in the first exports, as above.
    var measurementReminders: [MeasurementReminder]?

    /// e.g. "Medication Schedule 2026-10-21".
    /// Not named `suggestedFilename`: `Transferable` has a property by that name, and reading
    /// it inside `.suggestedFileName { }` recursed until the app crashed.
    var exportFilename: String {
        "Medication Schedule \(exportedAt.formatted(.iso8601.year().month().day()))"
    }

    static func encoded(_ export: ScheduleExport) throws -> Data {
        let encoder = JSONEncoder()
        // Readable, and stable between exports of the same schedule.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    static func decoded(from data: Data) throws -> ScheduleExport {
        let export: ScheduleExport
        do {
            export = try JSONDecoder().decode(ScheduleExport.self, from: data)
        } catch {
            throw ScheduleTransferError.unreadable
        }
        guard export.version <= currentVersion else { throw ScheduleTransferError.newerVersion }
        return export
    }

    /// Reads a user-selected file (from the document picker, so outside the sandbox).
    static func read(from url: URL) throws -> ScheduleExport {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try decoded(from: Data(contentsOf: url))
    }
}

/// An encoded schedule handed to the Files exporter. The app's types are main-actor
/// isolated and the exporter may ask for the data from any thread, so the JSON is
/// produced on the main actor first and this only passes it on.
nonisolated struct ScheduleExportFile: Transferable, Sendable {
    let data: Data
    let filename: String

    @MainActor
    init(_ export: ScheduleExport) throws {
        data = try ScheduleExport.encoded(export)
        filename = export.exportFilename
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

enum ScheduleTransferError: LocalizedError {
    case unreadable
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file isn't a medication schedule exported from Health Tracker."
        case .newerVersion: "This schedule was exported from a newer version of Health Tracker. Update the app to import it."
        }
    }
}

extension HealthStore {
    /// The current medications, daily routine, preferences and reminders, ready to export.
    func scheduleExport(now: Date = .now) -> ScheduleExport {
        ScheduleExport(exportedAt: now, medications: medications,
                       mealTimes: mealTimes, schedulePreferences: schedulePreferences,
                       medicationRemindersEnabled: medicationRemindersEnabled,
                       measurementReminders: measurementReminders)
    }

    /// Replaces the medication list, daily routine, preferences and reminders with an exported
    /// schedule, then reschedules reminders. Medications already present (same name) keep
    /// their identity and start date, so their logged doses stay linked.
    func applyScheduleImport(_ export: ScheduleExport, now: Date = .now) {
        mealTimes = export.mealTimes
        schedulePreferences = export.schedulePreferences
        medications = merged(export.medications)
        if let enabled = export.medicationRemindersEnabled {
            medicationRemindersEnabled = enabled
        }
        if let imported = export.measurementReminders {
            measurementReminders = importedMeasurementReminders(imported, now: now)
        }
    }

    /// One reminder per measurement type, taken from the file where it has one. A reminder
    /// that's newly on counts as active from now, so days before the import don't show its
    /// readings as missed; one that was already on keeps its start.
    private func importedMeasurementReminders(_ imported: [MeasurementReminder], now: Date) -> [MeasurementReminder] {
        measurementReminders.map { current in
            guard var reminder = imported.first(where: { $0.kind == current.kind }) else { return current }
            if reminder.isEnabled {
                reminder.activeSince = current.isEnabled ? current.activeSince : now
            }
            return reminder
        }
    }
}
