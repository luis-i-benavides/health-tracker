//
//  ScheduleTransferTests.swift
//  health-trackerTests
//
//  Exporting and reading back the medication schedule file.
//

import Foundation
import Testing
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
        var renamedCopy = existing
        renamedCopy.id = UUID()
        renamedCopy.name = existing.name.uppercased()

        let merged = store.merged([renamedCopy])
        #expect(merged.first?.id == existing.id)
    }
}
