//
//  HealthStore.swift
//  health-tracker
//

import Foundation
import Observation

/// A scheduled dose on a given day, paired with the log that satisfied it (if any).
struct DoseSlot: Identifiable, Hashable {
    let medication: Medication
    let time: TimeOfDay
    /// The full scheduled date and time.
    let date: Date
    let log: MedicationLog?

    var id: String { "\(medication.id.uuidString)-\(date.timeIntervalSinceReferenceDate)" }

    /// Not logged and its time has passed (for past days: missed).
    func isOverdue(now: Date = .now) -> Bool {
        log == nil && date < now
    }
}

/// A measurement reminder on a given day, paired with the reading that satisfied it (if any).
struct MeasurementSlot: Identifiable, Hashable {
    let kind: MeasurementKind
    let time: TimeOfDay
    /// The full scheduled date and time.
    let date: Date
    let log: MeasurementLog?

    var id: String { "\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)" }
}

/// In-memory app state. Persistence is not implemented yet.
@Observable
final class HealthStore {
    var medications: [Medication]
    var medicationLogs: [MedicationLog]
    var symptomLogs: [SymptomLog]
    var measurementLogs: [MeasurementLog]
    var measurementReminders: [MeasurementReminder]
    var medicationRemindersEnabled = true

    /// The most recent scheduling problem, shown by reminder screens.
    var lastSchedulingError: String?
    /// Incremented after each reschedule so views can refresh what's pending.
    private(set) var scheduleVersion = 0

    private let scheduler = NotificationScheduler()

    init(
        medications: [Medication] = [],
        medicationLogs: [MedicationLog] = [],
        symptomLogs: [SymptomLog] = [],
        measurementLogs: [MeasurementLog] = [],
        measurementReminders: [MeasurementReminder] = MeasurementKind.allCases.map {
            MeasurementReminder(kind: $0, times: [TimeOfDay(hour: 8, minute: 0)], isEnabled: false)
        }
    ) {
        self.medications = medications
        self.medicationLogs = medicationLogs
        self.symptomLogs = symptomLogs
        self.measurementLogs = measurementLogs
        self.measurementReminders = measurementReminders
    }

    static var preview: HealthStore {
        HealthStore(
            medications: SampleData.medications,
            medicationLogs: SampleData.medicationLogs,
            symptomLogs: SampleData.symptomLogs,
            measurementLogs: SampleData.measurementLogs,
            measurementReminders: SampleData.measurementReminders
        )
    }

    // MARK: - Queries

    func medication(for id: Medication.ID) -> Medication? {
        medications.first { $0.id == id }
    }

    // The schedule (medication times, reminder times) isn't versioned yet, so past days
    // are shown against the *current* schedule.

    /// A day's scheduled doses in time order, each paired with its log.
    func doses(on day: Date = .now, calendar: Calendar = .current) -> [DoseSlot] {
        let dayLogs = medicationLogs.filter {
            $0.scheduledTime != nil && calendar.isDate($0.scheduledDay, inSameDayAs: day)
        }
        return medications
            // No slots before the medication was added, so earlier days aren't full of "missed".
            .filter { calendar.startOfDay(for: $0.addedOn) <= calendar.startOfDay(for: day) }
            .flatMap { medication in
                medication.times.map { time in
                    let log = dayLogs.first { $0.medicationID == medication.id && $0.scheduledTime == time }
                    return DoseSlot(medication: medication, time: time, date: time.date(on: day, calendar: calendar), log: log)
                }
            }
            .sorted { $0.date < $1.date }
    }

    /// A day's doses that weren't tied to a scheduled slot (extra doses), with their medication.
    /// Also includes logs whose slot no longer exists (e.g. after re-importing the CSV).
    func extraDoses(on day: Date = .now, calendar: Calendar = .current) -> [(Medication, MedicationLog)] {
        let slotted = Set(doses(on: day, calendar: calendar).compactMap(\.log?.id))
        return medicationLogs
            .filter { calendar.isDate($0.scheduledTime == nil ? $0.takenAt : $0.scheduledDay, inSameDayAs: day) }
            .filter { !slotted.contains($0.id) }
            .compactMap { log in medication(for: log.medicationID).map { ($0, log) } }
    }

    /// A day's enabled measurement reminders, each paired with its reading if recorded.
    func measurementSlots(on day: Date = .now, calendar: Calendar = .current) -> [MeasurementSlot] {
        let dayLogs = measurementLogs.filter {
            $0.scheduledTime != nil && calendar.isDate($0.scheduledDay, inSameDayAs: day)
        }
        return measurementReminders
            .filter { $0.isEnabled && calendar.startOfDay(for: $0.activeSince) <= calendar.startOfDay(for: day) }
            .flatMap { reminder in
                reminder.times.map { time in
                    let log = dayLogs.first { $0.kind == reminder.kind && $0.scheduledTime == time }
                    return MeasurementSlot(kind: reminder.kind, time: time, date: time.date(on: day, calendar: calendar), log: log)
                }
            }
            .sorted { $0.date < $1.date }
    }

    /// A day's readings that weren't tied to a reminder, plus readings whose reminder
    /// was since turned off or rescheduled (so they never disappear from the timeline).
    func unscheduledMeasurements(on day: Date = .now, calendar: Calendar = .current) -> [MeasurementLog] {
        let slotted = Set(measurementSlots(on: day, calendar: calendar).compactMap(\.log?.id))
        return measurementLogs.filter {
            calendar.isDate($0.scheduledTime == nil ? $0.takenAt : $0.scheduledDay, inSameDayAs: day)
                && !slotted.contains($0.id)
        }
    }

    /// A day's symptoms, newest first.
    func symptoms(on day: Date = .now, calendar: Calendar = .current) -> [SymptomLog] {
        symptomLogs
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Logging

    func logDose(_ log: MedicationLog) {
        medicationLogs.append(log)
    }

    func logSymptom(_ log: SymptomLog) {
        symptomLogs.append(log)
    }

    func logMeasurement(_ log: MeasurementLog) {
        measurementLogs.append(log)
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
    /// Medications already in the list (matched by name) keep their identity and start date,
    /// so their logged history stays linked after re-importing an updated CSV.
    func applyImport(_ imported: [Medication]) async {
        medications = merged(imported)
        await rescheduleNotifications()
    }

    /// The imported list, with medications already present (same name) keeping their id and start date.
    func merged(_ imported: [Medication]) -> [Medication] {
        imported.map { new in
            guard let existing = medications.first(where: {
                $0.name.compare(new.name, options: .caseInsensitive) == .orderedSame
            }) else { return new }
            return Medication(
                id: existing.id, name: new.name, dosage: new.dosage, unit: new.unit,
                times: new.times, addedOn: existing.addedOn
            )
        }
    }

    // MARK: - Notifications

    func rescheduleNotifications() async {
        // Bump on every exit path, including when permission is denied.
        defer { scheduleVersion += 1 }
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
