//
//  ScheduleTransfer.swift
//  health-tracker
//
//  Exports the medication list, daily routine and schedule preferences as a JSON file, and
//  reads one back — e.g. to move a schedule to another device or keep a backup before
//  optimizing. Logged history (doses, readings, symptoms) isn't included.
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

    /// e.g. "Medication Schedule 2026-10-21".
    var suggestedFilename: String {
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

extension ScheduleExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .json) { try ScheduleExport.encoded($0) }
            importing: { try ScheduleExport.decoded(from: $0) }
            .suggestedFileName { $0.suggestedFilename }
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
    /// The current medications, daily routine and preferences, ready to export.
    func scheduleExport(now: Date = .now) -> ScheduleExport {
        ScheduleExport(exportedAt: now, medications: medications,
                       mealTimes: mealTimes, schedulePreferences: schedulePreferences)
    }

    /// Replaces the medication list, daily routine and preferences with an exported schedule,
    /// then reschedules reminders. Medications already present (same name) keep their
    /// identity and start date, as with a CSV import, so their logged doses stay linked.
    func applyScheduleImport(_ export: ScheduleExport) async {
        mealTimes = export.mealTimes
        schedulePreferences = export.schedulePreferences
        medications = merged(export.medications)
        await rescheduleNotifications()
    }
}
