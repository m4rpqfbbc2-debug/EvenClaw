// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// NotificationBridge.swift
//
// Pushes AI responses to iOS local notifications. The Even G2 (and any
// ANCS-compatible smart glasses) automatically mirrors iOS notifications
// to the glasses HUD. This gives us a zero-SDK display path.
//
// Usage:
//   await NotificationBridge.shared.requestPermission()
//   NotificationBridge.shared.pushToHUD(title: "AI", body: "Meeting at 3pm")
//

import UserNotifications
import Foundation

class NotificationBridge {

    // MARK: - Singleton

    static let shared = NotificationBridge()

    private let notificationCenter = UNUserNotificationCenter.current()

    /// Tracks whether we have notification permission.
    private(set) var isAuthorized = false

    private init() {}

    // MARK: - Permission

    /// Request notification permission. Call once at app launch.
    /// Returns true if granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                NSLog("[NotificationBridge] Permission granted")
            } else {
                NSLog("[NotificationBridge] Permission denied")
            }
            return granted
        } catch {
            NSLog("[NotificationBridge] Permission error: %@", error.localizedDescription)
            isAuthorized = false
            return false
        }
    }

    // MARK: - Display

    /// Push a text notification that glasses will mirror via ANCS.
    ///
    /// - Parameters:
    ///   - title: Short title line (e.g. "EvenClaw", "Weather")
    ///   - body: The main text content
    ///   - category: Notification category identifier for filtering
    func pushToHUD(title: String, body: String, category: String = "ai_response") {
        guard isAuthorized else {
            NSLog("[NotificationBridge] Not authorized — skipping notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        // Silent — the audio response comes from Gemini, not the notification
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        notificationCenter.add(request) { error in
            if let error {
                NSLog("[NotificationBridge] Failed to post: %@", error.localizedDescription)
            } else {
                NSLog("[NotificationBridge] Posted: %@ — %@", title, String(body.prefix(60)))
            }
        }
    }

    /// Remove all pending and delivered AI notifications.
    func clearHUD() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
        NSLog("[NotificationBridge] Cleared all notifications")
    }
}
