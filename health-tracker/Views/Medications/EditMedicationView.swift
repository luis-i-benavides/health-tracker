//
//  EditMedicationView.swift
//  health-tracker
//
//  Sheet for adding or editing a medication: every field an imported CSV row can set.
//

import SwiftUI

struct EditMedicationView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The medication being edited; `nil` when adding one.
    private let original: Medication?

    /// The kinds of `DoseSchedule`, for the picker.
    enum ScheduleKind: String, CaseIterable, Identifiable {
        case daily, everyHours, bedtime, weekly, asNeeded
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: "Daily"
            case .everyHours: "Every few hours"
            case .bedtime: "At bedtime"
            case .weekly: "Some weekdays"
            case .asNeeded: "As needed"
            }
        }
    }

    /// A time row with a stable identity, so editing one time doesn't re-create the others.
    private struct EditableTime: Identifiable {
        let id = UUID()
        var time: TimeOfDay
    }

    @State private var name: String
    @State private var genericName: String
    @State private var strengthText: String
    @State private var form: DoseForm
    @State private var quantity: Double
    @State private var route: Route
    @State private var scheduleKind: ScheduleKind
    @State private var times: [EditableTime]
    /// Daily schedules: how many doses a day, placed at meal times; `nil` for specific times.
    @State private var dosesPerDay: Int?
    @State private var interval: Int
    @State private var firstDose: TimeOfDay
    @State private var bedtime: TimeOfDay
    @State private var weekdays: Set<Weekday>
    @State private var minHoursApart: Double
    @State private var maxDoses: Int
    @State private var foodRules: Set<FoodRule>
    @State private var hasCourse: Bool
    @State private var courseStart: Date
    @State private var courseDays: Int
    @State private var purpose: String

    private let formatter = PrescriptionFormatter()
    /// Intervals that divide the day evenly.
    private static let intervals = [2, 3, 4, 6, 8, 12]

    init(medication: Medication?) {
        original = medication
        let med = medication
        _name = State(initialValue: med?.name ?? "")
        _genericName = State(initialValue: med?.genericName ?? "")
        _strengthText = State(initialValue: med?.strength.map { PrescriptionFormatter().strengthText($0) } ?? "")
        _form = State(initialValue: med?.form ?? .tablet)
        _quantity = State(initialValue: med?.quantity ?? 1)
        _route = State(initialValue: med?.route ?? .byMouth)
        _foodRules = State(initialValue: med?.foodRules ?? [])
        _hasCourse = State(initialValue: med?.course != nil)
        _courseStart = State(initialValue: med?.course?.startDate ?? Calendar.current.startOfDay(for: .now))
        _courseDays = State(initialValue: med?.course?.days ?? 7)
        _purpose = State(initialValue: med?.purpose ?? "")

        // Defaults for every schedule kind, then the medication's actual schedule on top.
        var kind = ScheduleKind.daily
        var times = [TimeOfDay(hour: 8, minute: 0)]
        var interval = 8
        var firstDose = TimeOfDay(hour: 6, minute: 0)
        var bedtime = TimeOfDay(hour: 22, minute: 0)
        var weekdays: Set<Weekday> = [.monday]
        var minHours = 4.0
        var maxDoses = 4
        switch med?.schedule {
        case .daily(let t): kind = .daily; times = t
        case .everyHours(let i, let first): kind = .everyHours; interval = i; firstDose = first
        case .atBedtime(let t): kind = .bedtime; bedtime = t
        case .weekly(let days, let t): kind = .weekly; weekdays = days; times = t
        case .asNeeded(let h, let m): kind = .asNeeded; minHours = h; maxDoses = m
        case nil: break
        }
        _scheduleKind = State(initialValue: kind)
        // New medications start as "once daily"; existing ones show their saved times.
        _dosesPerDay = State(initialValue: med == nil ? 1 : nil)
        _times = State(initialValue: times.sorted().map { EditableTime(time: $0) })
        _interval = State(initialValue: interval)
        _firstDose = State(initialValue: firstDose)
        _bedtime = State(initialValue: bedtime)
        _weekdays = State(initialValue: weekdays)
        _minHoursApart = State(initialValue: minHours)
        _maxDoses = State(initialValue: maxDoses)
    }

    // MARK: - Validation

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var strength: Strength? {
        let text = strengthText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Strength(parsing: text)
    }

    private var problems: [String] {
        var problems: [String] = []
        if trimmedName.isEmpty { problems.append("Enter a name.") }
        if !strengthText.trimmingCharacters(in: .whitespaces).isEmpty, strength == nil {
            problems.append("Strength should look like \"500 mg\", \"5 gr\", \"5 mg/5 mL\" or \"0.1%\".")
        }
        if scheduleKind == .weekly || (scheduleKind == .daily && dosesPerDay == nil) {
            if times.isEmpty { problems.append("Add at least one time.") }
            if Set(times.map(\.time)).count != times.count { problems.append("Two doses are at the same time.") }
        }
        if scheduleKind == .weekly, weekdays.isEmpty { problems.append("Choose at least one day.") }
        if foodRules.contains(.withFood), foodRules.contains(.emptyStomach) {
            problems.append("A medication can't be taken both with food and on an empty stomach.")
        }
        return problems
    }

    private var schedule: DoseSchedule {
        let sortedTimes = times.map(\.time).sorted()
        return switch scheduleKind {
        case .daily: .daily(times: dosesPerDay.map { store.mealTimes.doseTimes(perDay: $0) } ?? sortedTimes)
        case .everyHours: .everyHours(interval: interval, firstDose: firstDose)
        case .bedtime: .atBedtime(bedtime)
        case .weekly: .weekly(days: weekdays, times: sortedTimes)
        case .asNeeded: .asNeeded(minHoursApart: minHoursApart, maxDosesPer24h: maxDoses)
        }
    }

    /// What would be saved; also drives the instruction preview.
    private var draft: Medication {
        let generic = genericName.trimmingCharacters(in: .whitespaces)
        let purpose = purpose.trimmingCharacters(in: .whitespaces)
        return Medication(
            id: original?.id ?? UUID(),
            name: trimmedName.isEmpty ? "Medication" : trimmedName,
            genericName: generic.isEmpty ? nil : generic,
            strength: strength,
            form: form,
            quantity: quantity,
            route: route,
            schedule: schedule,
            foodRules: foodRules,
            course: hasCourse ? Course(startDate: courseStart, days: courseDays) : nil,
            purpose: purpose.isEmpty ? nil : purpose,
            addedOn: original?.addedOn ?? .now
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Generic name (optional)", text: $genericName)
                    TextField("For (optional), e.g. blood pressure", text: $purpose)
                } footer: {
                    if !trimmedName.isEmpty {
                        Text(formatter.instruction(for: draft))
                    }
                }

                doseSection
                scheduleSection
                foodSection
                courseSection

                if let original {
                    DeleteEntrySection(
                        entryName: "Medication",
                        message: Self.deletionMessage(for: original, in: store)
                    ) {
                        store.deleteMedication(id: original.id)
                        Task { await store.rescheduleNotifications() }
                        dismiss()
                    }
                }
            }
            .navigationTitle(original == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                DialogSaveButton(isEnabled: problems.isEmpty, action: save)
            }
            .onChange(of: form) {
                // Whole units only for forms that can't be split.
                if !(form.isSplittable || form == .milliliter) { quantity = max(1, quantity.rounded()) }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var doseSection: some View {
        Section {
            TextField("Strength, e.g. 500 mg", text: $strengthText)
                .autocorrectionDisabled()
            Picker("Form", selection: $form) {
                ForEach(DoseForm.allCases, id: \.self) { form in
                    Text(form.plural.sentenceCased).tag(form)
                }
            }
            let step = form.isSplittable || form == .milliliter ? 0.5 : 1
            Stepper(value: $quantity, in: step...100, step: step) {
                LabeledContent("Each dose", value: formatter.quantityText(quantity, form: form))
            }
            Picker("Route", selection: $route) {
                ForEach(Route.allCases, id: \.self) { route in
                    Text(route.label).tag(route)
                }
            }
        } header: {
            Text("Dose")
        } footer: {
            if let first = problems.first(where: { $0.hasPrefix("Strength") }) {
                Text(first).foregroundStyle(.red)
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Schedule", selection: $scheduleKind) {
                ForEach(ScheduleKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            switch scheduleKind {
            case .daily, .weekly:
                if scheduleKind == .weekly {
                    weekdayPicker
                } else {
                    Picker("How often", selection: $dosesPerDay) {
                        Text("Once daily").tag(Int?.some(1))
                        Text("Twice daily").tag(Int?.some(2))
                        Text("Three times daily").tag(Int?.some(3))
                        Text("Four times daily").tag(Int?.some(4))
                        Text("At specific times").tag(Int?.none)
                    }
                }
                if scheduleKind == .weekly || dosesPerDay == nil {
                    timeRows
                }
            case .everyHours:
                Picker("Every", selection: $interval) {
                    ForEach(Self.intervals, id: \.self) { hours in
                        Text("\(hours) hours").tag(hours)
                    }
                }
                DatePicker("First dose", selection: $firstDose.asDate, displayedComponents: .hourAndMinute)
            case .bedtime:
                DatePicker("Bedtime", selection: $bedtime.asDate, displayedComponents: .hourAndMinute)
            case .asNeeded:
                Stepper(value: $minHoursApart, in: 0.5...48, step: 0.5) {
                    LabeledContent("At least", value: "\(minHoursApart.formatted()) h apart")
                }
                Stepper(value: $maxDoses, in: 1...24) {
                    LabeledContent("At most", value: "\(maxDoses) a day")
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            let scheduleProblems = problems.filter { $0.contains("time") || $0.contains("day.") }
            if !scheduleProblems.isEmpty {
                Text(scheduleProblems.joined(separator: "\n")).foregroundStyle(.red)
            } else if scheduleKind == .daily, dosesPerDay != nil {
                Text("\(formatter.scheduleText(schedule).sentenceCased), at your meal times. Use Optimize Schedule to fine-tune them.")
            } else {
                Text(formatter.scheduleText(schedule).sentenceCased)
            }
        }
    }

    /// One picker per dose time, plus Add Time.
    @ViewBuilder
    private var timeRows: some View {
        ForEach($times) { $entry in
            DatePicker("Dose", selection: $entry.time.asDate, displayedComponents: .hourAndMinute)
        }
        .onDelete { times.remove(atOffsets: $0) }
        Button("Add Time", systemImage: "plus") {
            let last = times.map(\.time).max() ?? TimeOfDay(hour: 8, minute: 0)
            times.append(EditableTime(time: TimeOfDay(hour: min(last.hour + 4, 23), minute: last.minute)))
        }
    }

    /// Monday-first toggles for the weekly schedule.
    private var weekdayPicker: some View {
        HStack {
            ForEach(Weekday.allCases.sorted(), id: \.self) { day in
                let isOn = weekdays.contains(day)
                Button(String(day.name.prefix(2))) {
                    if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(isOn ? Color.white : Color.accentColor)
                .background(isOn ? Color.accentColor : Color.clear, in: .capsule)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var foodSection: some View {
        Section {
            ForEach(FoodRule.allCases, id: \.self) { rule in
                Toggle(foodLabel(rule), isOn: Binding(
                    get: { foodRules.contains(rule) },
                    set: { isOn in
                        if isOn { foodRules.insert(rule) } else { foodRules.remove(rule) }
                    }
                ))
            }
        } header: {
            Text("Food and Drink")
        } footer: {
            if let conflict = problems.first(where: { $0.contains("empty stomach") }) {
                Text(conflict).foregroundStyle(.red)
            }
        }
    }

    private var courseSection: some View {
        Section("Course") {
            Toggle("Fixed number of days", isOn: $hasCourse)
            if hasCourse {
                DatePicker("Starts", selection: $courseStart, displayedComponents: .date)
                Stepper(value: $courseDays, in: 1...365) {
                    LabeledContent("Length", value: "\(courseDays) day\(courseDays == 1 ? "" : "s")")
                }
            }
        }
    }

    private func foodLabel(_ rule: FoodRule) -> String {
        rule.phrase.trimmingCharacters(in: CharacterSet(charactersIn: ".")).sentenceCased
    }

    /// Confirmation text for deleting a medication; also used by the medication list.
    static func deletionMessage(for medication: Medication, in store: HealthStore) -> String {
        let count = store.logCount(for: medication.id)
        let history = count == 0 ? "" : " Its \(count) logged dose\(count == 1 ? "" : "s") will also be removed."
        return "Its reminders stop.\(history) This can't be undone."
    }

    // MARK: - Saving

    private func save() {
        let medication = draft
        if original == nil {
            store.addMedication(medication)
        } else {
            store.updateMedication(medication)
        }
        Task { await store.rescheduleNotifications() }
        dismiss()
    }
}

#Preview("Edit Medication – Daily") {
    EditMedicationView(medication: SampleData.metformin)
        .environment(HealthStore.preview)
}

#Preview("Edit Medication – As Needed") {
    EditMedicationView(medication: SampleData.albuterol)
        .environment(HealthStore.preview)
}

#Preview("Add Medication") {
    EditMedicationView(medication: nil)
        .environment(HealthStore.preview)
}
