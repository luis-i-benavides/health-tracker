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
    case nociceptivePain
    case neuropathicPain
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
        case .nociceptivePain: "Nociceptive pain"
        case .neuropathicPain: "Neuropathic pain"
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
        case .nociceptivePain: "bandage"
        case .neuropathicPain: "bolt"
        case .rash: "allergens"
        case .other: "ellipsis.circle"
        }
    }

    /// Pain types logged with where in the body they're felt.
    var hasBodyLocation: Bool {
        switch self {
        case .jointPain, .nociceptivePain, .neuropathicPain: true
        default: false
        }
    }
}

/// Where a pain symptom is felt.
enum BodyPart: String, CaseIterable, Identifiable, Codable {
    case upperBack, lowerBack, arms, legs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .arms: "Arms"
        case .legs: "Legs"
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
    /// For pain types; `nil` when not given. Optional so data saved before it existed still loads.
    var bodyPart: BodyPart?

    init(
        id: UUID = UUID(),
        type: SymptomType,
        customName: String = "",
        bodyPart: BodyPart? = nil,
        severity: Severity,
        date: Date = .now,
        note: String = ""
    ) {
        self.id = id
        self.type = type
        self.customName = customName
        self.bodyPart = type.hasBodyLocation ? bodyPart : nil
        self.severity = severity
        self.date = date
        self.note = note
    }

    /// e.g. "Headache", "Neuropathic pain (legs)", or the custom name for "Other".
    var displayName: String {
        let name = type == .other && !customName.isEmpty ? customName : type.label
        guard let bodyPart else { return name }
        return "\(name) (\(bodyPart.label.lowercased()))"
    }
}
