// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// CameraAccessApp.swift
//
// Main entry point for EvenClaw — AI assistant for Even Realities G2 smart glasses.
// Forked from VisionClaw (Meta Ray-Ban). The Meta DAT SDK has been replaced with
// a hardware abstraction layer (GlassesProvider) that supports multiple backends.
//

import Foundation
import SwiftUI

// NOTE: Meta DAT SDK imports removed — EvenClaw uses GlassesProvider abstraction instead.
// import MWDATCore
// import MWDATMockDevice

@main
struct CameraAccessApp: App {

    /// The glasses provider determines how display output is routed.
    /// Change this to switch between backends:
    ///   - PhoneOnlyProvider()       → no glasses, audio only
    ///   - NotificationProvider()    → ANCS notifications (works with any glasses)
    ///   - EvenG2Provider()          → Even Hub SDK (when available)
    @StateObject private var sessionManager = AISessionManager(
        glassesProvider: NotificationProvider()
    )

    var body: some Scene {
        WindowGroup {
            // TODO: Replace with EvenClaw-specific UI
            // For now, reuse the existing views with the new session manager
            MainAppView_EvenClaw(sessionManager: sessionManager)
        }
    }
}

/// Temporary top-level view for EvenClaw.
/// This wraps the existing GeminiSessionViewModel-based UI while we migrate.
struct MainAppView_EvenClaw: View {
    @ObservedObject var sessionManager: AISessionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Status header
                VStack(spacing: 8) {
                    Text("EvenClaw")
                        .font(.largeTitle.bold())

                    Text("AI Assistant for Even G2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Connection indicators
                    HStack(spacing: 16) {
                        StatusDot(
                            label: "Gemini",
                            isConnected: sessionManager.connectionState == .ready
                        )
                        StatusDot(
                            label: "OpenClaw",
                            isConnected: sessionManager.openClawConnectionState == .connected
                        )
                        StatusDot(
                            label: "Glasses",
                            isConnected: sessionManager.glassesConnectionState == .connected
                        )
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 40)

                Spacer()

                // Transcription display
                if !sessionManager.userTranscript.isEmpty {
                    Text(sessionManager.userTranscript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                if !sessionManager.aiTranscript.isEmpty {
                    Text(sessionManager.aiTranscript)
                        .font(.body.bold())
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                // Tool call status
                if case .executing(let name) = sessionManager.toolCallStatus {
                    HStack {
                        ProgressView()
                        Text("Running: \(name)")
                            .font(.caption)
                    }
                }

                Spacer()

                // Main action button
                Button {
                    Task {
                        if sessionManager.isActive {
                            sessionManager.stopSession()
                        } else {
                            await sessionManager.startSession()
                        }
                    }
                } label: {
                    Circle()
                        .fill(sessionManager.isActive ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: sessionManager.isActive ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                }
                .padding(.bottom, 60)

                // Error display
                if let error = sessionManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Simple status indicator dot.
struct StatusDot: View {
    let label: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
