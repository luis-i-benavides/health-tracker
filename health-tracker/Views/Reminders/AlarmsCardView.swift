//
//  AlarmsCardView.swift
//  health-tracker
//
//  Alarms for medication doses and measurements, in addition to notifications. While on, they
//  stay in sync with the schedule automatically, and notifications become silent.
//

import AVFoundation
import SwiftUI

struct AlarmsCardView: View {
    @Environment(HealthStore.self) private var store

    /// Plays the selected sound so the user can hear it before an alarm rings.
    @State private var previewPlayer: AVAudioPlayer?

    var body: some View {
        @Bindable var store = store
        let plan = store.alarmPlan
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.alarmSettings.isEnabled },
                set: { enabled in Task { await store.setAlarmsEnabled(enabled) } }
            )) {
                Label("Alarms", systemImage: "alarm.fill")
                    .font(.headline)
            }
            Text("Alarms ring even in Silent mode and can be snoozed. Medications and measurements due at the same time share one alarm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if store.alarmSettings.isEnabled {
                if plan.isEmpty {
                    Text("Nothing is scheduled. Add medications or turn on measurement reminders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan) { alarm in
                            alarmRow(alarm)
                        }
                    }
                }

                LabeledContent("Snooze") {
                    Picker("Snooze", selection: $store.alarmSettings.snoozeMinutes) {
                        ForEach(AlarmSettings.snoozeOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                LabeledContent("Sound") {
                    HStack(spacing: 4) {
                        Picker("Sound", selection: $store.alarmSettings.sound) {
                            ForEach(AlarmSound.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        if store.alarmSettings.sound.fileName != nil {
                            Button(previewPlayer == nil ? "Play" : "Stop",
                                   systemImage: previewPlayer == nil ? "play.circle" : "stop.circle") {
                                togglePreview()
                            }
                            .labelStyle(.iconOnly)
                            .font(.title3)
                        }
                    }
                }

                if store.scheduledAlarmCount > 0 {
                    Text("\(store.scheduledAlarmCount) alarm\(store.scheduledAlarmCount == 1 ? "" : "s") set. They update automatically when the schedule changes. Notifications stay silent while alarms are on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.lastAlarmError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .cardStyle()
        // A new snooze length or sound applies to every alarm, so they're recreated.
        .onChange(of: store.alarmSettings.sound) {
            stopPreview()
            Task { await store.refreshAlarms() }
        }
        .onChange(of: store.alarmSettings.snoozeMinutes) {
            Task { await store.refreshAlarms() }
        }
        .onDisappear { stopPreview() }
    }

    private func alarmRow(_ alarm: PlannedAlarm) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(alarm.time.date(), format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.title)
                    .font(.subheadline)
                Text(alarm.daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func togglePreview() {
        if previewPlayer != nil {
            stopPreview()
            return
        }
        guard let fileName = store.alarmSettings.sound.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return }
        // Play even when the ring/silent switch is set to silent, as the alarm itself will.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player.play()
        previewPlayer = player
        // A few seconds is enough to recognize the sound.
        Task {
            try? await Task.sleep(for: .seconds(6))
            if previewPlayer === player { stopPreview() }
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }
}

#Preview {
    ScrollView {
        AlarmsCardView()
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(HealthStore.preview)
}
