//
//  MedicationDetailView.swift
//  health-tracker
//
//  Read-only view of a medication's prescription: the instruction sentence, safety lines,
//  every structured field, course progress, and as-needed or reminder status.
//

import SwiftUI

struct MedicationDetailView: View {
    @Environment(HealthStore.self) private var store

    let medication: Medication

    private let formatter = PrescriptionFormatter()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatter.title(for: medication))
                        .font(.title3.bold())
                    Text(formatter.instruction(for: medication))
                }
                .padding(.vertical, 4)
                ForEach(formatter.warnings(for: medication), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if let course = medication.course {
                Section("Course") {
                    LabeledContent("Progress", value: courseProgress(course))
                    LabeledContent("Ends") {
                        Text(course.lastDay().formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            if let limits = store.asNeededStatus(for: medication) {
                Section("As needed") {
                    LabeledContent("Taken", value: formatter.statusText(limits))
                    Text(formatter.nextDoseText(limits))
                        .foregroundStyle(limits.nextAllowed == nil ? .green : .orange)
                }
            }

            if let lastReminder = store.coursesWithRemindersEndingEarly[medication.id] {
                Section {
                    Label {
                        Text("Reminders are scheduled through \(lastReminder.formatted(date: .abbreviated, time: .shortened)). Open the app before then to schedule the rest of the course.")
                    } icon: {
                        Image(systemName: "bell.badge")
                    }
                    .foregroundStyle(.orange)
                }
            }

            Section("Details") {
                if let generic = medication.genericName {
                    LabeledContent("Generic name", value: generic)
                }
                if let strength = medication.strength {
                    LabeledContent("Strength", value: formatter.strengthText(strength))
                }
                LabeledContent("Dose", value: formatter.doseText(for: medication))
                LabeledContent("Route", value: medication.route.label)
                LabeledContent("Schedule") {
                    Text(formatter.scheduleText(medication.schedule).sentenceCased)
                        .multilineTextAlignment(.trailing)
                }
                if !medication.foodRules.isEmpty {
                    LabeledContent("Food and drink") {
                        Text(medication.foodRules.sorted().map(foodLabel).joined(separator: "\n"))
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let purpose = medication.purpose {
                    LabeledContent("For", value: purpose)
                }
                LabeledContent("Started") {
                    Text(medication.addedOn.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Day 3 of 10", "Starts Oct 20", or "Finished Oct 19".
    private func courseProgress(_ course: Course) -> String {
        if let day = course.dayNumber(on: .now) {
            return "Day \(day) of \(course.days)"
        }
        if Date.now < course.startDate {
            return "Starts \(course.startDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Finished"
    }

    private func foodLabel(_ rule: FoodRule) -> String {
        let text = rule.phrase.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

#Preview("Medication – Daily") {
    NavigationStack {
        MedicationDetailView(medication: SampleData.metformin)
    }
    .environment(HealthStore.preview)
}

#Preview("Medication – Course") {
    NavigationStack {
        MedicationDetailView(medication: SampleData.amoxicillin)
    }
    .environment(HealthStore.preview)
}

#Preview("Medication – As Needed") {
    NavigationStack {
        MedicationDetailView(medication: SampleData.albuterol)
    }
    .environment(HealthStore.preview)
}
