//
//  health_trackerApp.swift
//  health-tracker
//
//  Created by Luis Benavides on 10/11/26.
//

import SwiftUI

@main
struct health_trackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HealthStore(persistence: .standard)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase) {
            // Roll course reminders forward (iOS limits how many can be queued at once).
            if scenePhase == .active {
                Task { await store.refreshRemindersIfAuthorized() }
            }
        }
    }
}
