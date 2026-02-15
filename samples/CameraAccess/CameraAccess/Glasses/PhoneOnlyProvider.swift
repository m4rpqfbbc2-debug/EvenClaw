// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// PhoneOnlyProvider.swift
//
// GlassesProvider implementation for when no glasses are connected.
// All display output is a no-op (audio is the only output channel).
// Used as the default/fallback provider.
//

import Foundation

class PhoneOnlyProvider: GlassesProvider {

    // MARK: - Capabilities

    let displayCapability: DisplayCapability = .none
    let audioCapability: AudioCapability = .phoneOnly
    let cameraCapability: CameraCapability = .phoneOnly
    let inputCapability: InputCapability = .none

    // MARK: - Connection

    /// Phone is always "connected" to itself
    var connectionState: GlassesConnectionState = .connected

    var onConnectionStateChanged: ((GlassesConnectionState) -> Void)?
    var onGesture: ((GlassesGesture) -> Void)?

    // MARK: - GlassesProvider

    func connect() async throws {
        connectionState = .connected
        onConnectionStateChanged?(.connected)
    }

    func disconnect() {
        connectionState = .disconnected
        onConnectionStateChanged?(.disconnected)
    }

    /// No display — no-op.
    func displayText(_ text: String, style: DisplayStyle) async throws {
        // No glasses display available. Audio output is the only channel.
    }

    /// No display — no-op.
    func clearDisplay() async throws {
        // Nothing to clear
    }
}
