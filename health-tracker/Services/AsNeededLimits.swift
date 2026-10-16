//
//  AsNeededLimits.swift
//  health-tracker
//
//  Checks an as-needed ("PRN") medication's limits over a rolling 24 hours:
//  the maximum number of doses and the minimum gap between doses.
//

import Foundation

/// Where an as-needed medication stands at a given moment.
struct AsNeededStatus: Hashable {
    /// Doses (not skipped) taken in the 24 hours before `time`.
    let dosesInLast24h: Int
    let maxDosesPer24h: Int
    let minHoursApart: Double
    /// Most recent dose at or before `time`.
    let lastDose: Date?
    /// Earliest time another dose stays within both limits; `nil` if one is allowed now.
    let nextAllowed: Date?

    var remainingDoses: Int { max(0, maxDosesPer24h - dosesInLast24h) }
}

enum AsNeededWarning: Hashable {
    /// Taking this dose would make `count` doses in 24 hours, over `max`.
    case overDailyMax(count: Int, max: Int)
    /// Less than the minimum gap since the last dose; the next dose is allowed at `nextAllowed`.
    case tooSoon(lastDose: Date, nextAllowed: Date)
}

enum AsNeededLimits {
    static let window: TimeInterval = 24 * 60 * 60

    /// Status of `medication` at `time`, from its logs. `nil` for scheduled medications.
    static func status(for medication: Medication, logs: [MedicationLog], at time: Date) -> AsNeededStatus? {
        guard case .asNeeded(let minHours, let maxDoses) = medication.schedule else { return nil }

        let taken = logs
            .filter { $0.medicationID == medication.id && $0.status != .skipped && $0.takenAt <= time }
            .map(\.takenAt)
            .sorted()
        let inWindow = taken.filter { $0 > time.addingTimeInterval(-window) }
        let lastDose = taken.last

        // Another dose is allowed once the gap since the last dose has passed, and once enough
        // doses have rolled out of the 24-hour window to make room for one more.
        var candidates: [Date] = []
        if let lastDose {
            candidates.append(lastDose.addingTimeInterval(minHours * 3600))
        }
        if inWindow.count >= maxDoses {
            // The (count - max + 1)th oldest dose in the window has to drop out.
            candidates.append(inWindow[inWindow.count - maxDoses].addingTimeInterval(window))
        }
        let next = candidates.max().flatMap { $0 > time ? $0 : nil }

        return AsNeededStatus(
            dosesInLast24h: inWindow.count,
            maxDosesPer24h: maxDoses,
            minHoursApart: minHours,
            lastDose: lastDose,
            nextAllowed: next
        )
    }

    /// Warnings for logging a dose of `medication` at `time`. Empty when within limits
    /// (or the medication isn't as-needed). Warnings never block logging; the user confirms.
    static func warnings(forDoseOf medication: Medication, logs: [MedicationLog], at time: Date) -> [AsNeededWarning] {
        guard let status = status(for: medication, logs: logs, at: time) else { return [] }
        var warnings: [AsNeededWarning] = []
        if status.dosesInLast24h + 1 > status.maxDosesPer24h {
            warnings.append(.overDailyMax(count: status.dosesInLast24h + 1, max: status.maxDosesPer24h))
        }
        if let lastDose = status.lastDose {
            let earliest = lastDose.addingTimeInterval(status.minHoursApart * 3600)
            if time < earliest {
                warnings.append(.tooSoon(lastDose: lastDose, nextAllowed: earliest))
            }
        }
        return warnings
    }
}

extension HealthStore {
    /// - Parameter excluding: a log being edited, so it isn't counted against itself.
    func asNeededStatus(
        for medication: Medication,
        at time: Date = .now,
        excluding excludedID: MedicationLog.ID? = nil
    ) -> AsNeededStatus? {
        let logs = medicationLogs.filter { $0.id != excludedID }
        return AsNeededLimits.status(for: medication, logs: logs, at: time)
    }

    /// - Parameter excluding: a log being edited, so it isn't counted against itself.
    func asNeededWarnings(
        forDoseOf medication: Medication,
        at time: Date = .now,
        excluding excludedID: MedicationLog.ID? = nil
    ) -> [AsNeededWarning] {
        let logs = medicationLogs.filter { $0.id != excludedID }
        return AsNeededLimits.warnings(forDoseOf: medication, logs: logs, at: time)
    }
}
