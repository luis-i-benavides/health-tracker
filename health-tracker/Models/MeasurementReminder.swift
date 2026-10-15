//
//  MeasurementReminder.swift
//  health-tracker
//

import SwiftUI

/// One numeric input of a measurement, e.g. "Systolic" for blood pressure.
struct MeasurementField: Hashable {
    let label: String
    let unit: String
    /// Physiologically plausible range, used to catch typos.
    let validRange: ClosedRange<Double>
}

enum MeasurementKind: String, CaseIterable, Identifiable {
    case bloodPressure
    case heartRate
    case oxygenSaturation
    case bloodGlucose
    case weight
    case temperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloodPressure: "Blood pressure"
        case .heartRate: "Heart rate"
        case .oxygenSaturation: "Oxygen saturation"
        case .bloodGlucose: "Blood glucose"
        case .weight: "Weight"
        case .temperature: "Temperature"
        }
    }

    var symbol: String {
        switch self {
        case .bloodPressure: "heart.text.square"
        case .heartRate: "waveform.path.ecg"
        case .oxygenSaturation: "lungs.fill"
        case .bloodGlucose: "drop"
        case .weight: "scalemass"
        case .temperature: "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .bloodPressure: .red
        case .heartRate: .pink
        case .oxygenSaturation: .cyan
        case .bloodGlucose: .purple
        case .weight: .teal
        case .temperature: .orange
        }
    }

    /// The values the user enters for this measurement. Weight and temperature
    /// follow the device's measurement system (US: lb / °F, otherwise kg / °C).
    var fields: [MeasurementField] {
        let usesUSUnits = Locale.current.measurementSystem == .us
        switch self {
        case .bloodPressure:
            return [
                MeasurementField(label: "Systolic", unit: "mmHg", validRange: 50...260),
                MeasurementField(label: "Diastolic", unit: "mmHg", validRange: 30...160),
            ]
        case .heartRate:
            return [MeasurementField(label: "Pulse", unit: "bpm", validRange: 25...250)]
        case .oxygenSaturation:
            return [MeasurementField(label: "SpO₂", unit: "%", validRange: 50...100)]
        case .bloodGlucose:
            return [MeasurementField(label: "Glucose", unit: "mg/dL", validRange: 20...600)]
        case .weight:
            return usesUSUnits
                ? [MeasurementField(label: "Weight", unit: "lb", validRange: 1...1000)]
                : [MeasurementField(label: "Weight", unit: "kg", validRange: 0.5...450)]
        case .temperature:
            return usesUSUnits
                ? [MeasurementField(label: "Temperature", unit: "°F", validRange: 90...110)]
                : [MeasurementField(label: "Temperature", unit: "°C", validRange: 32...43)]
        }
    }
}

struct MeasurementReminder: Identifiable, Hashable {
    var kind: MeasurementKind
    var times: [TimeOfDay]
    var isEnabled: Bool {
        didSet {
            if isEnabled && !oldValue { activeSince = .now }
        }
    }
    /// When the reminder was last turned on. Earlier days don't show its readings as missed;
    /// readings recorded before then still appear as unscheduled entries.
    var activeSince: Date = .now

    var id: MeasurementKind { kind }
}

/// A recorded reading, e.g. blood pressure 128/84 mmHg.
struct MeasurementLog: Identifiable, Hashable {
    let id: UUID
    var kind: MeasurementKind
    /// One value per `kind.fields` entry, in the same order.
    var values: [Double]
    /// Unit at the time of recording, so readings stay correct if the device's units change.
    var unit: String
    /// The reminder slot this reading satisfies; `nil` for an unscheduled reading.
    var scheduledTime: TimeOfDay?
    /// The day of the reminder slot (see `MedicationLog.scheduledDay`).
    var scheduledDay: Date
    var takenAt: Date
    var note: String

    init(
        id: UUID = UUID(),
        kind: MeasurementKind,
        values: [Double],
        unit: String,
        scheduledTime: TimeOfDay? = nil,
        scheduledDay: Date? = nil,
        takenAt: Date = .now,
        note: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.values = values
        self.unit = unit
        self.scheduledTime = scheduledTime
        self.scheduledDay = Calendar.current.startOfDay(for: scheduledDay ?? takenAt)
        self.takenAt = takenAt
        self.note = note
    }

    /// e.g. "128/84 mmHg", "97 %", "98.6 °F".
    var displayValue: String {
        let numbers = values.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
        return "\(numbers.joined(separator: "/")) \(unit)"
    }
}
