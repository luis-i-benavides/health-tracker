//
//  ScheduleTransferTests.swift
//  health-trackerTests
//
//  Exporting and reading back the medication schedule file.
//

import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import health_tracker

@MainActor
struct ScheduleTransferTests {
    private func sampleExport() -> ScheduleExport {
        let store = HealthStore.preview
        store.mealTimes.breakfast = TimeOfDay(hour: 7, minute: 15)
        store.schedulePreferences.coffeeTime = TimeOfDay(hour: 6, minute: 45)
        store.schedulePreferences.dairyMeals = [.breakfast, .dinner]
        store.schedulePreferences.workHours = SchedulePreferences.defaultWorkHours
        store.schedulePreferences.timePreference = .evening
        return store.scheduleExport()
    }

    @Test func exportRoundTripsEveryField() throws {
        let original = sampleExport()
        let decoded = try ScheduleExport.decoded(from: ScheduleExport.encoded(original))
        #expect(decoded == original)
        #expect(decoded.medications.contains { $0.course != nil })
        #expect(decoded.medications.contains { $0.schedule.isAsNeeded })
        #expect(decoded.schedulePreferences.dairyMeals == [.breakfast, .dinner])
        #expect(decoded.measurementReminders?.contains { $0.isEnabled } == true)
        #expect(decoded.medicationRemindersEnabled == true)
    }

    @Test func importReplacesRemindersAndStartsNewOnesNow() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = HealthStore()   // every measurement reminder off
        var export = sampleExport()
        export.medicationRemindersEnabled = false
        let enabledKinds = try #require(export.measurementReminders).filter(\.isEnabled).map(\.kind)
        #expect(!enabledKinds.isEmpty)

        store.applyScheduleImport(export, now: now)

        #expect(!store.medicationRemindersEnabled)
        #expect(store.measurementReminders.map(\.kind) == MeasurementKind.allCases)
        for reminder in store.measurementReminders where enabledKinds.contains(reminder.kind) {
            #expect(reminder.isEnabled)
            #expect(reminder.activeSince == now)
        }
        #expect(store.medications.map(\.name) == export.medications.map(\.name))
        #expect(store.schedulePreferences == export.schedulePreferences)
    }

    @Test func olderExportWithoutRemindersKeepsCurrentOnes() throws {
        let store = HealthStore.preview
        let before = store.measurementReminders
        // Shaped like the first exports, which had no reminder fields.
        var json = try #require(try JSONSerialization.jsonObject(
            with: ScheduleExport.encoded(sampleExport())) as? [String: Any])
        json["measurementReminders"] = nil
        json["medicationRemindersEnabled"] = nil
        let export = try ScheduleExport.decoded(from: JSONSerialization.data(withJSONObject: json))

        store.medicationRemindersEnabled = false
        store.applyScheduleImport(export)
        #expect(store.measurementReminders == before)
        #expect(!store.medicationRemindersEnabled)
    }

    /// What the Files exporter does: resolve the file name and read the data, off the main thread.
    @Test func exportFileDataCanBeReadOffTheMainThread() async throws {
        let original = sampleExport()
        let file = try ScheduleExportFile(original)
        let data = try await Task.detached { try await file.exported(as: .json) }.value
        #expect(try ScheduleExport.decoded(from: data) == original)
        #expect(file.filename == original.exportFilename)
        // Resolving the file name through Transferable once recursed until it crashed.
        #expect(file.suggestedFilename == original.exportFilename)
    }

    @Test func exportLeavesOutLoggedHistory() throws {
        let json = try #require(String(data: ScheduleExport.encoded(sampleExport()), encoding: .utf8))
        #expect(!json.contains("medicationLogs"))
        #expect(!json.contains("symptomLogs"))
    }

    @Test func fileThatIsntAScheduleIsRejected() {
        #expect(throws: ScheduleTransferError.unreadable) {
            try ScheduleExport.decoded(from: Data(#"{"hello": "world"}"#.utf8))
        }
    }

    @Test func newerVersionIsRejected() throws {
        var export = sampleExport()
        export.version = ScheduleExport.currentVersion + 1
        let data = try ScheduleExport.encoded(export)
        #expect(throws: ScheduleTransferError.newerVersion) { try ScheduleExport.decoded(from: data) }
    }

    @Test func importedMedicationsKeepExistingIdentityByName() throws {
        let store = HealthStore.preview
        let existing = try #require(store.medications.first)
        // Same medication from another device: different id, name in different case.
        let fromFile = Medication(name: existing.name.uppercased(), strength: existing.strength,
                                  schedule: existing.schedule)

        let merged = store.merged([fromFile])
        #expect(merged.first?.id == existing.id)
    }
}
