//
//  Symptom.swift
//  health-tracker
//

import SwiftUI

/// The predefined symptoms shown in the dropdown.
enum SymptomType: String, CaseIterable, Identifiable, Codable {
    case headache
    case nausea
    case dizziness
    case fatigue
    case chestPain
    case shortnessOfBreath
    case cough
    case insomnia
    case jointPain
    case rash
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .headache: "Headache"
        case .nausea: "Nausea"
        case .dizziness: "Dizziness"
        case .fatigue: "Fatigue"
        case .chestPain: "Chest pain"
        case .shortnessOfBreath: "Shortness of breath"
        case .cough: "Cough"
        case .insomnia: "Insomnia"
        case .jointPain: "Joint pain"
        case .rash: "Rash"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .headache: "brain.head.profile"
        case .nausea: "waveform.path"
        case .dizziness: "tornado"
        case .fatigue: "battery.25percent"
        case .chestPain: "heart"
        case .shortnessOfBreath: "lungs"
        case .cough: "wind"
        case .insomnia: "moon.zzz"
        case .jointPain: "figure.walk"
        case .rash: "allergens"
        case .other: "ellipsis.circle"
        }
    }
}

enum Severity: Int, CaseIterable, Identifiable, Comparable, Codable {
    case mild = 1
    case moderate = 2
    case severe = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    var color: Color {
        switch self {
        case .mild: .green
        case .moderate: .orange
        case .severe: .red
        }
    }

    /// Maps a 1–10 pain-style score to a severity bucket.
    init(score: Int) {
        switch score {
        case ...3: self = .mild
        case 4...6: self = .moderate
        default: self = .severe
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SymptomLog: Identifiable, Hashable, Codable {
    let id: UUID
    var type: SymptomType
    /// Free text used when `type` is `.other`.
    var customName: String
    var severity: Severity
    var date: Date
    var note: String

    init(
        id: UUID = UUID(),
        type: SymptomType,
        customName: String = "",
        severity: Severity,
        date: Date = .now,
        note: String = ""
    ) {
        self.id = id
        self.type = type
        self.customName = customName
        self.severity = severity
        self.date = date
        self.note = note
    }

    var displayName: String {
        type == .other && !customName.isEmpty ? customName : type.label
    }
}
