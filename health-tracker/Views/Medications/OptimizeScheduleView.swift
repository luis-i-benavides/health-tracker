//
//  OptimizeScheduleView.swift
//  health-tracker
//
//  Sheet that asks Claude for better dose times and shows the suggestion — before/after
//  times, reasons and warnings — for the user to apply or dismiss.
//

import SwiftUI

struct OptimizeScheduleView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = KeychainStore.anthropicAPIKey.read() ?? ""
    @State private var isEditingKey = (KeychainStore.anthropicAPIKey.read() ?? "").isEmpty
    /// Free-text instructions added to the request, e.g. "I take my walk at 6 pm".
    @State private var instructions = ""
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var proposal: ScheduleProposal?
    @State private var isApplying = false
    /// Asking to apply a schedule whose doses break a separation.
    @State private var isConfirmingViolations = false

    /// Preloaded suggestion, for previews.
    init(proposal: ScheduleProposal? = nil) {
        _proposal = State(initialValue: proposal)
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                if let proposal {
                    proposalSections(proposal)
                } else {
                    DailyRoutineSection(mealTimes: $store.mealTimes)
                    SchedulePreferencesSection(preferences: $store.schedulePreferences)
                    instructionsSection
                    apiKeySection
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(proposal == nil ? "Optimize Schedule" : "Suggested Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if proposal != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Start Over") { proposal = nil }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomButton
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isRequesting)
        .alert("Some Doses Are Too Close", isPresented: $isConfirmingViolations) {
            Button("Apply Anyway", role: .destructive, action: applyProposal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some suggested times break the separations listed under Kept Apart, so one medication may not be absorbed properly. Check with your pharmacist before applying.")
        }
    }

    // MARK: - Before asking

    private var instructionsSection: some View {
        Section {
            TextField("e.g. I'd rather take everything after breakfast", text: $instructions, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Additional Instructions")
        } footer: {
            Text("Optional. Claude follows these when it can, but never at the expense of safety or your prescriptions.")
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            if isEditingKey {
                SecureField("Anthropic API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(saveKey)
                Button("Save Key", action: saveKey)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                LabeledContent("API key", value: "Saved in Keychain")
                Button("Change Key") { isEditingKey = true }
                Button("Remove Key", role: .destructive) {
                    KeychainStore.anthropicAPIKey.delete()
                    apiKey = ""
                    isEditingKey = true
                }
            }
        } header: {
            Text("Claude")
        } footer: {
            Text("Your medication list, daily routine, any instructions you add and the last 14 days of symptoms are sent to Anthropic's Claude (\(ScheduleOptimizer.model)) to make the suggestion. Nothing changes until you apply it.")
        }
    }

    private func saveKey() {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        KeychainStore.anthropicAPIKey.save(apiKey)
        isEditingKey = false
    }

    // MARK: - The suggestion

    @ViewBuilder
    private func proposalSections(_ proposal: ScheduleProposal) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(proposal.distinctTimesBefore) → \(proposal.distinctTimesAfter)")
                        .font(.headline)
                    Text("Dose times a day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Text(proposal.summary)
        }

        if !proposal.warnings.isEmpty {
            Section("Things to Know") {
                ForEach(proposal.warnings) { warning in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(warning.message)
                            if !warning.medicationNames.isEmpty {
                                Text(warning.medicationNames.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: icon(for: warning.severity))
                            .foregroundStyle(color(for: warning.severity))
                    }
                }
            }
        }

        if !proposal.separations.isEmpty {
            Section {
                ForEach(proposal.separations) { separation in
                    separationRow(separation)
                }
            } header: {
                Text("Kept Apart")
            } footer: {
                Text("Medications, vitamins and foods that reduce each other's absorption. The app checks each suggested time against these gaps.")
            }
        }

        Section("Medications") {
            ForEach(proposal.changes) { change in
                changeRow(change)
            }
        }
    }

    private func separationRow(_ separation: ProposalSeparation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("\(separation.affectedName.sentenceCased) and \(separation.blockerName)")
                    .font(.headline)
            } icon: {
                Image(systemName: separation.isSatisfied ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(separation.isSatisfied ? .green : .red)
            }
            Text(gapText(separation))
                .font(.subheadline)
            if !separation.reason.isEmpty {
                Text(separation.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(separation.violations, id: \.self) { violation in
                Text(violation)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let unchecked = separation.uncheckedReason {
                Text(unchecked)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// e.g. "Take vitamin D at least 1 h before or 4 h after cholestyramine."
    private func gapText(_ separation: ProposalSeparation) -> String {
        func hours(_ value: Double) -> String { "\(value.formatted()) h" }
        let affected = separation.affectedName
        let blocker = separation.blockerName
        switch (separation.hoursBefore > 0, separation.hoursAfter > 0) {
        case (true, true): return "\(affected.sentenceCased) at least \(hours(separation.hoursBefore)) before or \(hours(separation.hoursAfter)) after \(blocker)."
        case (true, false): return "\(affected.sentenceCased) at least \(hours(separation.hoursBefore)) before \(blocker)."
        case (false, true): return "\(affected.sentenceCased) at least \(hours(separation.hoursAfter)) after \(blocker)."
        case (false, false): return "\(affected.sentenceCased) can be taken with \(blocker)."
        }
    }

    private func changeRow(_ change: ProposedScheduleChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(change.medication.name).font(.headline)
                Spacer()
                if change.changesSomething {
                    Text("Changed").font(.caption.bold()).foregroundStyle(.tint)
                }
            }
            HStack(spacing: 6) {
                Text(timeList(change.oldTimes))
                    .foregroundStyle(.secondary)
                    .strikethrough(change.newTimes != change.oldTimes && change.problem == nil)
                if change.problem == nil, change.newTimes != change.oldTimes {
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(timeList(change.newTimes)).fontWeight(.semibold)
                }
            }
            .font(.subheadline.monospacedDigit())
            if change.addsWithFood {
                Label("Take with food", systemImage: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            if !change.reason.isEmpty {
                Text(change.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(change.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let problem = change.problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bottom button

    @ViewBuilder
    private var bottomButton: some View {
        if let proposal {
            DialogSaveButton(title: proposal.hasChanges ? "Apply Schedule" : "Done",
                             isEnabled: !isApplying) {
                guard proposal.hasChanges else { dismiss(); return }
                if proposal.hasSeparationViolations {
                    isConfirmingViolations = true
                } else {
                    applyProposal()
                }
            }
        } else if isRequesting {
            VStack(spacing: 6) {
                ProgressView()
                Text("Claude is working out your schedule. This can take a minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        } else {
            DialogSaveButton(title: "Suggest Schedule",
                             isEnabled: !apiKey.isEmpty && !isEditingKey && !store.medications.isEmpty,
                             action: requestSuggestion)
        }
    }

    private func applyProposal() {
        guard let proposal else { return }
        isApplying = true
        Task {
            await store.apply(proposal)
            dismiss()
        }
    }

    private func requestSuggestion() {
        errorMessage = nil
        isRequesting = true
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let symptoms = store.symptomLogs.filter { $0.date >= since }
        Task {
            defer { isRequesting = false }
            do {
                proposal = try await ScheduleOptimizer(apiKey: apiKey).propose(
                    medications: store.medications,
                    mealTimes: store.mealTimes,
                    preferences: store.schedulePreferences,
                    recentSymptoms: symptoms,
                    instructions: instructions
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Formatting

    private func timeList(_ times: [TimeOfDay]) -> String {
        times.sorted().map(\.displayText).joined(separator: ", ")
    }

    private func icon(for severity: ScheduleSuggestion.Warning.Severity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .important: "exclamationmark.octagon.fill"
        }
    }

    private func color(for severity: ScheduleSuggestion.Warning.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .caution: .orange
        case .important: .red
        }
    }
}

#Preview("Optimize – Start") {
    OptimizeScheduleView()
        .environment(HealthStore.preview)
}

#Preview("Optimize – Absorption") {
    OptimizeScheduleView(proposal: SampleData.absorptionProposal)
        .environment(HealthStore.preview)
}

#Preview("Optimize – Suggestion") {
    OptimizeScheduleView(proposal: SampleData.scheduleProposal)
        .environment(HealthStore.preview)
}
