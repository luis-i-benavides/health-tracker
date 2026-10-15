//
//  AppDelegate.swift
//  health-tracker
//

import UIKit
import UserNotifications

/// Installs the notification delegate at launch, as UserNotifications requires.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Without this, iOS silently drops notifications that arrive while the app is open,
    /// so a dose or measurement reminder would never appear if you're using the app at that time.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
