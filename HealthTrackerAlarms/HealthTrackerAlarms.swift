//
//  HealthTrackerAlarms.swift
//  HealthTrackerAlarms
//
//  The Live Activity AlarmKit shows while a medication alarm is snoozed: on the Lock Screen,
//  in StandBy, and in the Dynamic Island. AlarmKit requires it for alarms that can snooze.
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct MedicationAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MedicationAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "pills.fill")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText(context.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(label(context.attributes))
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                remainingTime(context.state)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(context.attributes.tintColor)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(statusText(context.state), systemImage: "pills.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remainingTime(context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(label(context.attributes))
                        .font(.subheadline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                remainingTime(context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    private func label(_ attributes: AlarmAttributes<MedicationAlarmMetadata>) -> String {
        attributes.metadata?.label ?? "Medication alarm"
    }

    private func statusText(_ state: AlarmPresentationState) -> String {
        switch state.mode {
        case .countdown: "Snoozed"
        case .alert: "Now"
        default: "Paused"
        }
    }

    /// Time left until a snoozed alarm rings again.
    @ViewBuilder
    private func remainingTime(_ state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}
