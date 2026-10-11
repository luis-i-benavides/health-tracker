//
//  HealthStore.swift
//  health-tracker
//

import Foundation
import Observation

/// A scheduled dose for today, paired with the log that satisfied it (if any).
struct DoseSlot: Identifiable, Hashable {
    let medication: Medication
    let time: TimeOfDay
    let log: MedicationLog?

    var id: String { "\(medication.id.uuidString)-\(time.id)" }

    func isOverdue(now: Date = .now) -> Bool {
        log == nil && time.date(on: now) < now
    }
}

/// An upcoming reminder of any kind, used by the schedule-style layouts.
struct ScheduleItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case medication(Medication)
        case measurement(MeasurementKind)
    }

    let kind: Kind
    let time: TimeOfDay

    var id: String {
        switch kind {
        case .medication(let medication): "med-\(medication.id.uuidString)-\(time.id)"
        case .measurement(let measurement): "measure-\(measurement.rawValue)-\(time.id)"
        }
    }
}

/// In-memory app state. Persistence will be added once a design is chosen.
@Observable
final class HealthStore {
    var medications: [Medication]
    var medicationLogs: [MedicationLog]
    var symptomLogs: [SymptomLog]
    var measurementReminders: [MeasurementReminder]
    var medicationRemindersEnabled = true

    /// The most recent scheduling problem, shown by reminder screens.
    var lastSchedulingError: String?

    private let scheduler = NotificationScheduler()

    init(
        medications: [Medication] = [],
        medicationLogs: [MedicationLog] = [],
        symptomLogs: [SymptomLog] = [],
        measurementReminders: [MeasurementReminder] = MeasurementKind.allCases.map {
            MeasurementReminder(kind: $0, times: [TimeOfDay(hour: 8, minute: 0)], isEnabled: false)
        }
    ) {
        self.medications = medications
        self.medicationLogs = medicationLogs
        self.symptomLogs = symptomLogs
        self.measurementReminders = measurementReminders
    }

    static var preview: HealthStore {
        HealthStore(
            medications: SampleData.medications,
            medicationLogs: SampleData.medicationLogs,
            symptomLogs: SampleData.symptomLogs,
            measurementReminders: SampleData.measurementReminders
        )
    }

    // MARK: - Queries

    func medication(for id: Medication.ID) -> Medication? {
        medications.first { $0.id == id }
    }

    /// All of today's scheduled doses in time order.
    func todaysDoses(calendar: Calendar = .current, now: Date = .now) -> [DoseSlot] {
        let todaysLogs = medicationLogs.filter { calendar.isDate($0.takenAt, inSameDayAs: now) }
        return medications
            .flatMap { medication in
                medication.times.map { time in
                    let log = todaysLogs.first { $0.medicationID == medication.id && $0.scheduledTime == time }
                    return DoseSlot(medication: medication, time: time, log: log)
                }
            }
            .sorted { $0.time < $1.time }
    }

    /// Symptoms logged today, newest first.
    func todaysSymptoms(calendar: Calendar = .current, now: Date = .now) -> [SymptomLog] {
        symptomLogs
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date > $1.date }
    }

    /// Every enabled reminder (medications and measurements) for a day, in time order.
    func dailySchedule() -> [ScheduleItem] {
        let meds = medicationRemindersEnabled
            ? medications.flatMap { med in med.times.map { ScheduleItem(kind: .medication(med), time: $0) } }
            : []
        let measures = measurementReminders.filter(\.isEnabled).flatMap { reminder in
            reminder.times.map { ScheduleItem(kind: .measurement(reminder.kind), time: $0) }
        }
        return (meds + measures).sorted { $0.time < $1.time }
    }

    // MARK: - Logging

    func logDose(_ log: MedicationLog) {
        medicationLogs.append(log)
    }

    func logSymptom(_ log: SymptomLog) {
        symptomLogs.append(log)
    }

    // MARK: - Import

    /// Reads a user-selected CSV file and returns the parse result without applying it.
    func readCSV(from url: URL) throws -> CSVParseResult {
        // Files from the document picker are outside the sandbox and need scoped access.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        return CSVMedicationParser.parse(text)
    }

    /// Replaces the medication list and reschedules notifications.
    func applyImport(_ imported: [Medication]) async {
        medications = imported
        await rescheduleNotifications()
    }

    // MARK: - Notifications

    func rescheduleNotifications() async {
        do {
            guard try await scheduler.requestAuthorization() else {
                lastSchedulingError = "Notifications are turned off for Health Tracker in Settings."
                return
            }
            try await scheduler.reschedule(
                medications: medicationRemindersEnabled ? medications : [],
                measurementReminders: measurementReminders
            )
            lastSchedulingError = nil
        } catch {
            lastSchedulingError = error.localizedDescription
        }
    }
}
