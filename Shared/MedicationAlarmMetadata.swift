//
//  MedicationAlarmMetadata.swift
//  health-tracker
//
//  Shared by the app (which schedules alarms) and the HealthTrackerAlarms extension (which
//  draws the snooze countdown on the Lock Screen and in the Dynamic Island). Both must use
//  this same type so the system can match alarms to their Live Activity.
//

import AlarmKit

nonisolated struct MedicationAlarmMetadata: AlarmMetadata {
    /// What's due, e.g. "Take Metformin, Lisinopril · Measure blood pressure".
    var label: String
}
