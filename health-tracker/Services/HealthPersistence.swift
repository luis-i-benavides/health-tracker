//
//  HealthPersistence.swift
//  health-tracker
//
//  Saves the app's data (medications, dose/reading/symptom history, reminder settings) as one
//  JSON file in Application Support. The data is small, so the whole snapshot is rewritten
//  atomically on each change.
//
//  Compatibility: enum cases are stored by raw value and structs by property name, so renaming
//  either breaks loading older files. Add new properties as optionals (or bump `currentVersion`
//  and migrate) instead.
//

import Foundation
import os

/// Everything the app saves.
struct HealthSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version = HealthSnapshot.currentVersion
    var medications: [Medication]
    var medicationLogs: [MedicationLog]
    var symptomLogs: [SymptomLog]
    var measurementLogs: [MeasurementLog]
    var measurementReminders: [MeasurementReminder]
    var medicationRemindersEnabled: Bool
    /// Added after version 1 shipped; `nil` in older files.
    var mealTimes: MealTimes?
    /// Added after version 1 shipped; `nil` in older files.
    var schedulePreferences: SchedulePreferences?
    /// Added after version 1 shipped; `nil` in older files.
    var alarmSettings: AlarmSettings?
}

struct HealthPersistence {
    let fileURL: URL

    private static let logger = Logger(subsystem: "luisbenavides.health-tracker", category: "Persistence")

    /// `Application Support/HealthData.json`.
    static var standard: HealthPersistence {
        let directory = URL.applicationSupportDirectory
        return HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
    }

    /// The saved snapshot, or `nil` when nothing has been saved yet. A file that can't be
    /// read is moved aside (`HealthData.unreadable-<date>.json`) so it isn't overwritten,
    /// and the app starts empty.
    func load() -> HealthSnapshot? {
        // `path(percentEncoded: false)`: the default `path()` encodes the space in
        // "Application Support" as %20, so the file would never be found.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder.health.decode(HealthSnapshot.self, from: data)
            guard snapshot.version <= HealthSnapshot.currentVersion else {
                Self.logger.error("Saved data is from a newer version (\(snapshot.version)); not loading it.")
                quarantine()
                return nil
            }
            return snapshot
        } catch {
            Self.logger.error("Couldn't read saved data: \(error.localizedDescription)")
            quarantine()
            return nil
        }
    }

    func save(_ snapshot: HealthSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONEncoder.health.encode(snapshot)
        // Atomic so a crash mid-write can't leave a half-written file; health data stays
        // encrypted while the device is locked.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func quarantine() {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appending(path: "HealthData.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

// Dates use the default encoding (seconds since 2001 as a full-precision number) rather than
// ISO 8601, which drops fractional seconds, so saved times round-trip exactly.
private extension JSONEncoder {
    static var health: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var health: JSONDecoder { JSONDecoder() }
}
