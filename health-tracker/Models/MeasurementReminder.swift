//
//  MeasurementReminder.swift
//  health-tracker
//

import SwiftUI

enum MeasurementKind: String, CaseIterable, Identifiable {
    case bloodPressure
    case heartRate
    case bloodGlucose
    case weight
    case temperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloodPressure: "Blood pressure"
        case .heartRate: "Heart rate"
        case .bloodGlucose: "Blood glucose"
        case .weight: "Weight"
        case .temperature: "Temperature"
        }
    }

    var symbol: String {
        switch self {
        case .bloodPressure: "heart.text.square"
        case .heartRate: "waveform.path.ecg"
        case .bloodGlucose: "drop"
        case .weight: "scalemass"
        case .temperature: "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .bloodPressure: .red
        case .heartRate: .pink
        case .bloodGlucose: .purple
        case .weight: .teal
        case .temperature: .orange
        }
    }
}

struct MeasurementReminder: Identifiable, Hashable {
    var kind: MeasurementKind
    var times: [TimeOfDay]
    var isEnabled: Bool

    var id: MeasurementKind { kind }
}
