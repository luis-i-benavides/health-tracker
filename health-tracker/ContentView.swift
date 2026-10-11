//
//  ContentView.swift
//  health-tracker
//
//  Created by Luis Benavides on 10/11/26.
//

import SwiftUI

/// App shell using the chosen layout for each screen.
/// Logging a dose happens from the Today timeline via `LogMedicationQuickView`.
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "heart.text.clipboard") {
                TodayTimelineView()
            }
            Tab("Symptoms", systemImage: "stethoscope") {
                LogSymptomCompactView()
            }
            Tab("Reminders", systemImage: "bell") {
                RemindersCardView()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportCSVStepsView()
            }
        }
    }
}

#Preview("App – Default") {
    ContentView()
        .environment(HealthStore.preview)
}
