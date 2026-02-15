// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// NotificationProvider.swift
//
// GlassesProvider implementation that uses iOS notifications (ANCS) to
// display text on any compatible smart glasses. This is the primary
// display path for Even G2 until the native SDK is available.
//
// Since notifications work without pairing to a specific device,
// this provider always reports .connected state.
//

import Foundation

class NotificationProvider: GlassesProvider {

    // MARK: - Capabilities

    /// ANCS notifications support ~100 chars of readable text on most glasses
    let displayCapability: DisplayCapability = .textOnly(maxChars: 100)

    /// Audio stays on iPhone — no glasses audio routing without SDK
    let audioCapability: AudioCapability = .phoneOnly

    /// Even G2 has no camera; always use iPhone
    let cameraCapability: CameraCapability = .phoneOnly

    /// No gesture input without SDK
    let inputCapability: InputCapability = .none

    // MARK: - Connection

    /// Notifications work as long as iOS grants permission — no pairing needed
    var connectionState: GlassesConnectionState = .connected

    var onConnectionStateChanged: ((GlassesConnectionState) -> Void)?
    var onGesture: ((GlassesGesture) -> Void)?

    // MARK: - Private

    private let bridge = NotificationBridge.shared

    // MARK: - GlassesProvider

    /// Request notification permission. Always succeeds in terms of "connection"
    /// since the notification system is always available.
    func connect() async throws {
        connectionState = .connecting
        onConnectionStateChanged?(.connecting)

        let granted = await bridge.requestPermission()

        if granted {
            connectionState = .connected
            onConnectionStateChanged?(.connected)
            NSLog("[NotificationProvider] Connected (notifications authorized)")
        } else {
            // Even without permission, we're "connected" — the pipeline works,
            // notifications just won't show. User can fix in Settings.
            connectionState = .connected
            onConnectionStateChanged?(.connected)
            NSLog("[NotificationProvider] Connected (notifications denied — HUD won't display)")
        }
    }

    func disconnect() {
        bridge.clearHUD()
        connectionState = .disconnected
        onConnectionStateChanged?(.disconnected)
        NSLog("[NotificationProvider] Disconnected")
    }

    /// Push text to the glasses via iOS notification.
    func displayText(_ text: String, style: DisplayStyle) async throws {
        let title = style.title ?? "EvenClaw"
        bridge.pushToHUD(title: title, body: text, category: "ai_response")
    }

    /// Clear all notifications from the HUD.
    func clearDisplay() async throws {
        bridge.clearHUD()
    }
}
