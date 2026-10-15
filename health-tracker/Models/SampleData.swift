//
//  SampleData.swift
//  health-tracker
//

import Foundation

/// Sample content shared by all previews.
enum SampleData {
    /// Sample medications and reminders start a month ago so past days in previews have a schedule.
    static let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

    static let lisinopril = Medication(
        name: "Lisinopril", dosage: 10, unit: "mg",
        times: [TimeOfDay(hour: 8, minute: 0)],
        addedOn: monthAgo
    )
    static let metformin = Medication(
        name: "Metformin", dosage: 500, unit: "mg",
        times: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
        addedOn: monthAgo
    )
    static let atorvastatin = Medication(
        name: "Atorvastatin", dosage: 20, unit: "mg",
        times: [TimeOfDay(hour: 21, minute: 30)],
        addedOn: monthAgo
    )
    static let vitaminD = Medication(
        name: "Vitamin D3", dosage: 1000, unit: "IU",
        times: [TimeOfDay(hour: 12, minute: 0)],
        addedOn: monthAgo
    )

    static let medications = [lisinopril, metformin, atorvastatin, vitaminD]

    static var medicationLogs: [MedicationLog] {
        let today = Date.now
        return [
            MedicationLog(
                medicationID: lisinopril.id,
                scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 12).date(on: today),
                quantityTaken: 1, status: .taken
            ),
            MedicationLog(
                medicationID: metformin.id,
                scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 15).date(on: today),
                quantityTaken: 0.5, status: .partial,
                note: "Only had half a tablet left — refill needed."
            ),
            // Yesterday: most doses taken, the evening Metformin late, Atorvastatin missed.
            MedicationLog(
                medicationID: lisinopril.id, scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 3).date(on: yesterday),
                quantityTaken: 1, status: .taken
            ),
            MedicationLog(
                medicationID: metformin.id, scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 3).date(on: yesterday),
                quantityTaken: 1, status: .taken
            ),
            MedicationLog(
                medicationID: vitaminD.id, scheduledTime: TimeOfDay(hour: 12, minute: 0),
                takenAt: TimeOfDay(hour: 12, minute: 20).date(on: yesterday),
                quantityTaken: 1, status: .taken
            ),
            MedicationLog(
                medicationID: metformin.id, scheduledTime: TimeOfDay(hour: 20, minute: 0),
                takenAt: TimeOfDay(hour: 21, minute: 10).date(on: yesterday),
                quantityTaken: 1, status: .taken,
                note: "Forgot until after dinner."
            ),
        ]
    }

    static var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    }

    static var symptomLogs: [SymptomLog] {
        let today = Date.now
        return [
            SymptomLog(
                type: .headache, severity: .moderate,
                date: TimeOfDay(hour: 10, minute: 30).date(on: today),
                note: "Behind the eyes, started mid-morning."
            ),
            SymptomLog(
                type: .dizziness, severity: .mild,
                date: TimeOfDay(hour: 7, minute: 45).date(on: today),
                note: "When standing up quickly."
            ),
            SymptomLog(
                type: .nausea, severity: .mild,
                date: TimeOfDay(hour: 9, minute: 0).date(on: yesterday),
                note: "After morning Metformin on an empty stomach."
            ),
        ]
    }

    static var measurementLogs: [MeasurementLog] {
        let today = Date.now
        return [
            MeasurementLog(
                kind: .bloodPressure, values: [128, 84], unit: "mmHg",
                scheduledTime: TimeOfDay(hour: 7, minute: 30),
                takenAt: TimeOfDay(hour: 7, minute: 34).date(on: today),
                note: "Left arm, seated."
            ),
            MeasurementLog(
                kind: .bloodGlucose, values: [104], unit: "mg/dL",
                scheduledTime: TimeOfDay(hour: 7, minute: 0),
                takenAt: TimeOfDay(hour: 7, minute: 5).date(on: today)
            ),
            MeasurementLog(
                kind: .oxygenSaturation, values: [95], unit: "%",
                takenAt: TimeOfDay(hour: 9, minute: 15).date(on: today),
                note: "After climbing stairs."
            ),
            MeasurementLog(
                kind: .bloodPressure, values: [132, 86], unit: "mmHg",
                scheduledTime: TimeOfDay(hour: 7, minute: 30),
                takenAt: TimeOfDay(hour: 7, minute: 41).date(on: yesterday)
            ),
            MeasurementLog(
                kind: .bloodGlucose, values: [112], unit: "mg/dL",
                scheduledTime: TimeOfDay(hour: 7, minute: 0),
                takenAt: TimeOfDay(hour: 7, minute: 2).date(on: yesterday)
            ),
        ]
    }

    static let measurementReminders = [
        MeasurementReminder(
            kind: .bloodPressure,
            times: [TimeOfDay(hour: 7, minute: 30), TimeOfDay(hour: 19, minute: 30)],
            isEnabled: true,
            activeSince: monthAgo
        ),
        MeasurementReminder(
            kind: .bloodGlucose,
            times: [TimeOfDay(hour: 7, minute: 0)],
            isEnabled: true,
            activeSince: monthAgo
        ),
        MeasurementReminder(
            kind: .weight,
            times: [TimeOfDay(hour: 6, minute: 45)],
            isEnabled: false,
            activeSince: monthAgo
        ),
    ]

    static let csv = """
    name,dosage,unit,times
    Lisinopril,10,mg,08:00
    Metformin,500,mg,08:00;20:00
    "Vitamin D3, chewable",1000,IU,12:00
    Atorvastatin,twenty,mg,21:30
    Aspirin,81,mg,25:00
    """
}
