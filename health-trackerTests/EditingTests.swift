//
//  EditingTests.swift
//  health-trackerTests
//

import Foundation
import Testing
@testable import health_tracker

@MainActor
struct EditingTests {
    private let morning = TimeOfDay(hour: 8, minute: 0)

    @Test func updatingADoseReplacesItInPlace() {
        let store = HealthStore(medications: [SampleData.lisinopril])
        let original = MedicationLog(medicationID: SampleData.lisinopril.id, scheduledTime: morning,
                                     quantityTaken: 1, status: .taken)
        store.logDose(original)
        store.logDose(MedicationLog(medicationID: SampleData.lisinopril.id, scheduledTime: nil,
                                    quantityTaken: 1, status: .extra))

        var edited = original
        edited.status = .partial
        edited.quantityTaken = 0.5
        edited.note = "Felt dizzy"
        store.updateDose(edited)

        #expect(store.medicationLogs.count == 2)
        #expect(store.medicationLogs[0] == edited)
    }

    @Test func deletingAScheduledDoseReturnsTheSlotToNotLogged() throws {
        let store = HealthStore(medications: [SampleData.lisinopril])
        let log = MedicationLog(medicationID: SampleData.lisinopril.id, scheduledTime: SampleData.lisinopril.times[0],
                                quantityTaken: 1, status: .taken)
        store.logDose(log)
        #expect(store.doses().first?.log == log)

        store.deleteDose(id: log.id)
        #expect(store.medicationLogs.isEmpty)
        let slot = try #require(store.doses().first)
        #expect(slot.log == nil)
    }

    @Test func updatingAnUnknownEntryDoesNothing() {
        let store = HealthStore()
        store.updateDose(MedicationLog(medicationID: UUID(), scheduledTime: nil, quantityTaken: 1, status: .extra))
        store.updateSymptom(SymptomLog(type: .cough, severity: .mild))
        store.updateMeasurement(MeasurementLog(kind: .heartRate, values: [70], unit: "bpm"))
        #expect(store.medicationLogs.isEmpty)
        #expect(store.symptomLogs.isEmpty)
        #expect(store.measurementLogs.isEmpty)
    }

    @Test func symptomsCanBeEditedAndDeleted() {
        let store = HealthStore()
        let log = SymptomLog(type: .headache, severity: .mild)
        store.logSymptom(log)

        var edited = log
        edited.severity = .severe
        edited.note = "Worse after lunch"
        store.updateSymptom(edited)
        #expect(store.symptomLogs == [edited])

        store.deleteSymptom(id: log.id)
        #expect(store.symptomLogs.isEmpty)
    }

    @Test func readingsCanBeEditedAndDeleted() {
        let store = HealthStore()
        let log = MeasurementLog(kind: .bloodPressure, values: [182, 84], unit: "mmHg")
        store.logMeasurement(log)

        var edited = log
        edited.values = [128, 84]
        store.updateMeasurement(edited)
        #expect(store.measurementLogs.map(\.values) == [[128, 84]])

        store.deleteMeasurement(id: log.id)
        #expect(store.measurementLogs.isEmpty)
    }

    @Test func editedDoseIsNotCountedAgainstItsOwnLimits() {
        let store = HealthStore(medications: [SampleData.albuterol])
        let now = Date.now
        let log = MedicationLog(medicationID: SampleData.albuterol.id, scheduledTime: nil,
                                takenAt: now, quantityTaken: 2, status: .extra)
        store.logDose(log)

        // As a new dose at the same time it would be too soon...
        #expect(!store.asNeededWarnings(forDoseOf: SampleData.albuterol, at: now).isEmpty)
        // ...but editing the dose itself raises no warning.
        #expect(store.asNeededWarnings(forDoseOf: SampleData.albuterol, at: now, excluding: log.id).isEmpty)
        let status = store.asNeededStatus(for: SampleData.albuterol, at: now, excluding: log.id)
        #expect(status?.dosesInLast24h == 0)
    }

    @Test func editsAndDeletesAreSaved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Editing Tests \(UUID().uuidString)")
        let persistence = HealthPersistence(fileURL: directory.appending(path: "HealthData.json"))
        let store = HealthStore(persistence: persistence)
        let symptom = SymptomLog(type: .nausea, severity: .mild)
        let reading = MeasurementLog(kind: .heartRate, values: [72], unit: "bpm")
        store.logSymptom(symptom)
        store.logMeasurement(reading)

        var edited = symptom
        edited.severity = .moderate
        store.updateSymptom(edited)
        store.deleteMeasurement(id: reading.id)

        let reopened = HealthStore(persistence: persistence)
        #expect(reopened.symptomLogs == [edited])
        #expect(reopened.measurementLogs.isEmpty)
    }
}
