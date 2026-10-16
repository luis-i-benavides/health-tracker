//
//  ContentView.swift
//  health-tracker
//
//  Created by Luis Benavides on 10/11/26.
//

import SwiftUI

/// App shell. Doses, measurements and symptoms are all logged and browsed from the
/// Today timeline, which can be filtered to one category.
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "heart.text.clipboard") {
                TodayTimelineView()
            }
            Tab("Medications", systemImage: "pills") {
                MedicationsView()
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
