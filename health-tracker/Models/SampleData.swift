//
//  SampleData.swift
//  health-tracker
//

import Foundation

/// Sample content shared by all previews.
enum SampleData {
    /// Sample medications and reminders start a month ago so past days in previews have a schedule.
    static let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

    private static func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    static let lisinopril = Medication(
        name: "Lisinopril", strength: Strength(value: 10, unit: "mg"),
        schedule: .daily(times: [t(8)]), purpose: "blood pressure", addedOn: monthAgo
    )
    static let metformin = Medication(
        name: "Metformin", strength: Strength(value: 500, unit: "mg"),
        schedule: .daily(times: [t(8), t(20)]), foodRules: [.withFood, .avoidAlcohol],
        purpose: "diabetes", addedOn: monthAgo
    )
    static let atorvastatin = Medication(
        name: "Atorvastatin", strength: Strength(value: 20, unit: "mg"),
        schedule: .atBedtime(t(21, 30)), foodRules: [.avoidGrapefruit],
        purpose: "cholesterol", addedOn: monthAgo
    )
    static let vitaminD = Medication(
        name: "Vitamin D3", strength: Strength(value: 1000, unit: "IU"),
        schedule: .daily(times: [t(12)]), foodRules: [.withFood], addedOn: monthAgo
    )
    /// A 10-day antibiotic course that started 2 days ago (so today is day 3).
    static let amoxicillin = Medication(
        name: "Amoxicillin", strength: Strength(value: 500, unit: "mg"), form: .capsule,
        schedule: .daily(times: [t(8), t(14), t(20)]), foodRules: [.withFood],
        course: Course(startDate: daysAgo(2), days: 10), purpose: "infection", addedOn: daysAgo(2)
    )
    /// As needed, at most 3 doses (6 puffs) in 24 hours.
    static let albuterol = Medication(
        name: "Albuterol HFA", strength: Strength(value: 90, unit: "mcg"), form: .puff, quantity: 2,
        route: .inhaled, schedule: .asNeeded(minHoursApart: 4, maxDosesPer24h: 3),
        purpose: "wheezing", addedOn: monthAgo
    )
    static let latanoprost = Medication(
        name: "Latanoprost", strength: Strength(value: 0.005, unit: "%"), form: .drop,
        route: .eye, schedule: .atBedtime(t(22)), purpose: "glaucoma", addedOn: monthAgo
    )

    static let medications = [lisinopril, metformin, atorvastatin, vitaminD, amoxicillin, albuterol, latanoprost]

    static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }

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
            MedicationLog(
                medicationID: albuterol.id, scheduledTime: nil,
                takenAt: .now.addingTimeInterval(-5 * 3600), quantityTaken: 2, status: .extra,
                note: "Wheezy after climbing stairs."
            ),
            MedicationLog(
                medicationID: albuterol.id, scheduledTime: nil,
                takenAt: .now.addingTimeInterval(-1 * 3600), quantityTaken: 2, status: .extra
            ),
            MedicationLog(
                medicationID: amoxicillin.id, scheduledTime: TimeOfDay(hour: 8, minute: 0),
                takenAt: TimeOfDay(hour: 8, minute: 5).date(on: today), quantityTaken: 1, status: .taken
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

    /// Prescription-format CSV for the import preview: four valid rows and two with errors.
    static let csv = """
    name,strength,form,quantity,route,frequency,food,max_per_24h,duration_days,purpose
    Metformin,500 mg,tablet,1,by mouth,twice daily,with food;avoid alcohol,,,diabetes
    Amoxicillin,500 mg,capsule,1,by mouth,TID,with food,,10,infection
    Albuterol HFA,90 mcg,puff,2,inhaled,as needed,,3,,wheezing
    Latanoprost,0.005%,drop,1,eye,at bedtime,,,,glaucoma
    Aspirin,81,tablet,1,by mouth,once daily,,,,
    Ibuprofen,200 mg,tablet,1,by mouth,as needed,,,,pain
    """
}

extension SampleData {
    /// A suggestion like one Claude might return for the sample medications, checked the
    /// same way a real one is (keys follow `SampleData.medications` order).
    static var scheduleProposal: ScheduleProposal {
        let suggestion = ScheduleSuggestion(
            summary: "Your doses move to four times a day: breakfast, lunch, dinner and bedtime. Metformin and amoxicillin, which can upset the stomach, are taken with meals.",
            medications: [
                .init(key: "m1", times: ["08:00"], takeWithFood: false,
                      reason: "Morning dosing keeps blood pressure controlled through the day."),
                .init(key: "m2", times: ["08:00", "19:00"], takeWithFood: false,
                      reason: "Moved the evening dose to dinner, since it must be taken with food."),
                .init(key: "m3", times: ["22:30"], takeWithFood: false,
                      reason: "Bedtime, together with your eye drops."),
                .init(key: "m4", times: ["08:00"], takeWithFood: false,
                      reason: "Vitamin D is absorbed best with a meal; breakfast joins your other morning doses."),
                .init(key: "m5", times: ["08:00", "12:30", "19:00"], takeWithFood: false,
                      reason: "Three doses with meals reduce nausea and stomach upset."),
                .init(key: "m7", times: ["22:30"], takeWithFood: false,
                      reason: "Eye drops work best at bedtime."),
            ],
            warnings: [
                .init(severity: .caution,
                      message: "Amoxicillin often causes nausea. You don't have a scheduled anti-nausea medication; if nausea continues, ask your prescriber.",
                      medicationKeys: ["m5"]),
                .init(severity: .info,
                      message: "Avoid grapefruit with atorvastatin.",
                      medicationKeys: ["m3"]),
            ]
        )
        return ScheduleOptimizer.proposal(
            from: suggestion,
            keyed: ScheduleOptimizer.keyed(medications),
            mealTimes: MealTimes.standard
        )
    }
}
