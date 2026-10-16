//
//  PersistenceTests.swift
//  health-trackerTests
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct PersistenceTests {
    /// A fresh, empty folder per test so tests never touch the app's real data.
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "Persistence Tests \(UUID().uuidString)")

    private var persistence: HealthPersistence {
        HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
    }

    private func sampleSnapshot() -> HealthSnapshot {
        HealthStore.preview.snapshot
    }

    @Test func snapshotRoundTripsEveryField() throws {
        let original = sampleSnapshot()
        try persistence.save(original)
        let loaded = try #require(persistence.load())
        #expect(loaded == original)
        // Spot-check the parts most likely to be lost in encoding.
        #expect(loaded.medications.contains { $0.course != nil })
        #expect(loaded.medications.contains { $0.schedule.isAsNeeded })
        #expect(loaded.medicationLogs.contains { $0.quantityTaken == 0.5 })
    }

    @Test func nothingSavedYetLoadsNothing() {
        #expect(persistence.load() == nil)
        let store = HealthStore(persistence: persistence)
        #expect(store.medications.isEmpty)
        #expect(store.medicationLogs.isEmpty)
        #expect(store.medicationRemindersEnabled)
        #expect(store.measurementReminders.map(\.kind) == MeasurementKind.allCases)
    }

    @Test func changesAreSavedAndReloaded() throws {
        let store = HealthStore(persistence: persistence)
        store.medications = [SampleData.amoxicillin, SampleData.albuterol]
        store.logDose(MedicationLog(medicationID: SampleData.albuterol.id, scheduledTime: nil,
                                    quantityTaken: 2, status: .extra, confirmedOverLimit: true))
        store.logSymptom(SymptomLog(type: .nausea, severity: .mild, note: "After breakfast"))
        store.logMeasurement(MeasurementLog(kind: .bloodPressure, values: [128, 84], unit: "mmHg"))
        store.measurementReminders[0].isEnabled = true
        store.medicationRemindersEnabled = false

        // A new store (like the next app launch) sees the same data.
        let reopened = HealthStore(persistence: persistence)
        #expect(reopened.medications == store.medications)
        #expect(reopened.medicationLogs == store.medicationLogs)
        #expect(reopened.medicationLogs.first?.confirmedOverLimit == true)
        #expect(reopened.symptomLogs.map(\.note) == ["After breakfast"])
        #expect(reopened.measurementLogs.first?.values == [128, 84])
        #expect(reopened.measurementReminders[0].isEnabled)
        #expect(!reopened.medicationRemindersEnabled)
    }

    @Test func unreadableFileIsSetAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: persistence.fileURL)

        let store = HealthStore(persistence: persistence)
        #expect(store.medications.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.contains { $0.hasPrefix("HealthData.unreadable-") })
        #expect(!files.contains("HealthData.json"))
    }

    @Test func dataFromANewerVersionIsNotLoaded() throws {
        var future = sampleSnapshot()
        future.version = HealthSnapshot.currentVersion + 1
        try persistence.save(future)
        #expect(persistence.load() == nil)
    }

    @Test func missingMeasurementTypesAreAddedOnLoad() throws {
        var snapshot = sampleSnapshot()
        snapshot.measurementReminders = [
            MeasurementReminder(kind: .bloodPressure, times: [TimeOfDay(hour: 7, minute: 30)], isEnabled: true),
        ]
        try persistence.save(snapshot)
        let store = HealthStore(persistence: persistence)
        #expect(store.measurementReminders.map(\.kind) == MeasurementKind.allCases)
        #expect(store.measurementReminders.first { $0.kind == .bloodPressure }?.isEnabled == true)
    }

    @Test func standardLocationIsApplicationSupport() {
        let url = HealthPersistence.standard.fileURL
        #expect(url.lastPathComponent == "HealthData.json")
        #expect(url.path(percentEncoded: false).contains("/Application Support/"))
    }

    @Test func inMemoryStoresDoNotWriteFiles() {
        let store = HealthStore()
        store.medications = [SampleData.lisinopril]
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }
}
