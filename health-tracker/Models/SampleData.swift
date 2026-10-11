//
//  SampleData.swift
//  health-tracker
//

import Foundation

/// Sample content shared by all previews.
enum SampleData {
    static let lisinopril = Medication(
        name: "Lisinopril", dosage: 10, unit: "mg",
        times: [TimeOfDay(hour: 8, minute: 0)]
    )
    static let metformin = Medication(
        name: "Metformin", dosage: 500, unit: "mg",
        times: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)]
    )
    static let atorvastatin = Medication(
        name: "Atorvastatin", dosage: 20, unit: "mg",
        times: [TimeOfDay(hour: 21, minute: 30)]
    )
    static let vitaminD = Medication(
        name: "Vitamin D3", dosage: 1000, unit: "IU",
        times: [TimeOfDay(hour: 12, minute: 0)]
    )

    static let medications = [lisinopril, metformin, atorvastatin, vitaminD]

    static var medicationLogs: [MedicationLog] {
        let today = Date.now
        return [
            MedicationLog(
                medicationID: lisinopril.id,
                scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 12).date(on: today),
                amountTaken: 10, unit: "mg", status: .taken
            ),
            MedicationLog(
                medicationID: metformin.id,
                scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 15).date(on: today),
                amountTaken: 250, unit: "mg", status: .partial,
                note: "Only had half a tablet left — refill needed."
            ),
        ]
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
        ]
    }

    static let measurementReminders = [
        MeasurementReminder(
            kind: .bloodPressure,
            times: [TimeOfDay(hour: 7, minute: 30), TimeOfDay(hour: 19, minute: 30)],
            isEnabled: true
        ),
        MeasurementReminder(
            kind: .bloodGlucose,
            times: [TimeOfDay(hour: 7, minute: 0)],
            isEnabled: true
        ),
        MeasurementReminder(
            kind: .weight,
            times: [TimeOfDay(hour: 6, minute: 45)],
            isEnabled: false
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
