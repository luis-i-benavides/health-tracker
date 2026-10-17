//
//  HealthStore.swift
//  health-tracker
//

import Foundation
import Observation
import UserNotifications

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
    // Saved data: each change is written to disk when the store has a persistence location.
    var medications: [Medication] { didSet { save() } }
    var medicationLogs: [MedicationLog] { didSet { save() } }
    var symptomLogs: [SymptomLog] { didSet { save() } }
    var measurementLogs: [MeasurementLog] { didSet { save() } }
    var measurementReminders: [MeasurementReminder] { didSet { save() } }
    var medicationRemindersEnabled = true { didSet { save() } }
    var mealTimes = MealTimes.standard { didSet { save() } }
    var schedulePreferences = SchedulePreferences.standard { didSet { save() } }

    /// The most recent problem writing data to disk, if any.
    private(set) var lastSaveError: String?

    /// The most recent scheduling problem, shown by reminder screens.
    var lastSchedulingError: String?
    /// Incremented after each reschedule so views can refresh what's pending.
    private(set) var scheduleVersion = 0
    /// Courses whose remaining doses didn't all fit in iOS's 64-notification limit, with the
    /// last dose that does have a reminder. Topped up each time the app becomes active.
    private(set) var coursesWithRemindersEndingEarly: [Medication.ID: Date] = [:]

    private let scheduler = NotificationScheduler()
    /// Where data is saved; `nil` keeps everything in memory (previews and tests).
    private let persistence: HealthPersistence?

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
        self.persistence = nil
    }

    /// Loads saved data from `persistence` (if any) and saves every later change there.
    init(persistence: HealthPersistence) {
        let saved = persistence.load()
        self.medications = saved?.medications ?? []
        self.medicationLogs = saved?.medicationLogs ?? []
        self.symptomLogs = saved?.symptomLogs ?? []
        self.measurementLogs = saved?.measurementLogs ?? []
        // Keep one reminder per measurement type, including types added since the data was saved.
        let savedReminders = saved?.measurementReminders ?? []
        self.measurementReminders = MeasurementKind.allCases.map { kind in
            savedReminders.first { $0.kind == kind }
                ?? MeasurementReminder(kind: kind, times: [TimeOfDay(hour: 8, minute: 0)], isEnabled: false)
        }
        self.medicationRemindersEnabled = saved?.medicationRemindersEnabled ?? true
        self.mealTimes = saved?.mealTimes ?? .standard
        self.schedulePreferences = saved?.schedulePreferences ?? .standard
        self.persistence = persistence
    }

    /// The data that gets saved.
    var snapshot: HealthSnapshot {
        HealthSnapshot(
            medications: medications,
            medicationLogs: medicationLogs,
            symptomLogs: symptomLogs,
            measurementLogs: measurementLogs,
            measurementReminders: measurementReminders,
            medicationRemindersEnabled: medicationRemindersEnabled,
            mealTimes: mealTimes,
            schedulePreferences: schedulePreferences
        )
    }

    private func save() {
        guard let persistence else { return }
        do {
            try persistence.save(snapshot)
            lastSaveError = nil
        } catch {
            lastSaveError = "Couldn't save your data: \(error.localizedDescription)"
        }
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
            // Respects start date, course length and weekdays; as-needed medications have no slots.
            .filter { $0.isScheduled(on: day, calendar: calendar) }
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

    // MARK: - Editing

    // Updates replace the entry with the same id (keeping its place); deletes remove it.
    // Deleting a dose or reading tied to a scheduled slot returns that slot to due/missed.

    func updateDose(_ log: MedicationLog) {
        guard let index = medicationLogs.firstIndex(where: { $0.id == log.id }) else { return }
        medicationLogs[index] = log
    }

    func deleteDose(id: MedicationLog.ID) {
        medicationLogs.removeAll { $0.id == id }
    }

    func updateSymptom(_ log: SymptomLog) {
        guard let index = symptomLogs.firstIndex(where: { $0.id == log.id }) else { return }
        symptomLogs[index] = log
    }

    func deleteSymptom(id: SymptomLog.ID) {
        symptomLogs.removeAll { $0.id == id }
    }

    func updateMeasurement(_ log: MeasurementLog) {
        guard let index = measurementLogs.firstIndex(where: { $0.id == log.id }) else { return }
        measurementLogs[index] = log
    }

    func deleteMeasurement(id: MeasurementLog.ID) {
        measurementLogs.removeAll { $0.id == id }
    }

    // MARK: - Medications

    // Callers reschedule reminders afterwards (`rescheduleNotifications()`).

    func addMedication(_ medication: Medication) {
        medications.append(medication)
    }

    func updateMedication(_ medication: Medication) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        medications[index] = medication
    }

    /// Removes the medication and its logged doses, which would otherwise be orphaned.
    func deleteMedication(id: Medication.ID) {
        medications.removeAll { $0.id == id }
        medicationLogs.removeAll { $0.medicationID == id }
    }

    /// Logged doses of a medication, e.g. to warn before deleting it.
    func logCount(for id: Medication.ID) -> Int {
        medicationLogs.count { $0.medicationID == id }
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
            return new.adoptingIdentity(of: existing)
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
            let plan = try await scheduler.reschedule(
                medications: medicationRemindersEnabled ? medications : [],
                measurementReminders: measurementReminders
            )
            coursesWithRemindersEndingEarly = plan.lastScheduledDose
            lastSchedulingError = nil
        } catch {
            lastSchedulingError = error.localizedDescription
        }
    }

    /// Re-plans reminders when the app becomes active, so course reminders roll forward.
    /// Never prompts for permission. Skipped while no medications are loaded, so that if saved
    /// data ever fails to load, the reminders still pending from before aren't deleted.
    func refreshRemindersIfAuthorized() async {
        guard !medications.isEmpty else { return }
        switch await scheduler.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            await rescheduleNotifications()
        default:
            break
        }
    }
}
