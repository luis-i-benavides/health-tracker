//
//  health_trackerApp.swift
//  health-tracker
//
//  Created by Luis Benavides on 10/11/26.
//

import SwiftUI

@main
struct health_trackerApp: App {
    @State private var store = HealthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
