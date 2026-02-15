// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClaw App — Voice-to-HUD assistant for Even Realities G2 glasses.
// Mic → Whisper → OpenClaw → HUD notification + TTS.

import SwiftUI

@main
struct EvenClawApp: App {
    @StateObject private var manager = VoiceCommandManager(
        glassesProvider: EvenG2Provider()
    )

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager)
                .task { await manager.setup() }
        }
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var manager: VoiceCommandManager
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 4) {
                    Text("EvenClaw")
                        .font(.largeTitle.bold())
                    Text("Voice Assistant for Even G2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Status dots
                HStack(spacing: 20) {
                    StatusDot(label: "OpenClaw", isConnected: manager.openClawConnected)
                    StatusDot(label: "Glasses", isConnected: manager.glassesConnected)
                }
                
                // Debug info
                if !manager.debugStatus.isEmpty {
                    Text(manager.debugStatus)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Current State Display
                VStack(spacing: 12) {
                    // State indicator
                    Text(stateDisplayText)
                        .font(.title2.bold())
                        .foregroundStyle(stateColor)
                    
                    // Live transcription during listening
                    if manager.currentState == .listening && !manager.liveTranscriptionText.isEmpty {
                        VStack(spacing: 4) {
                            Text("Live transcription (\(transcriptionSourceText)):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(manager.liveTranscriptionText)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 8)
                        .background(transcriptionSourceColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Final transcription
                    if !manager.lastTranscription.isEmpty && manager.currentState != .listening {
                        VStack(spacing: 4) {
                            Text("You said:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(manager.lastTranscription)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Response
                    if !manager.lastResponse.isEmpty {
                        VStack(spacing: 4) {
                            Text("Response:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(manager.lastResponse)
                                .font(.body.bold())
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .lineLimit(6)
                        }
                    }

                    // Processing indicator
                    if manager.currentState == .processing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Processing…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Mic button
                Button {
                    manager.toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 88, height: 88)
                            .shadow(color: micButtonColor.opacity(0.4), radius: manager.isListening ? 12 : 4)

                        Group {
                            switch manager.currentState {
                            case .processing:
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                            case .listening:
                                Image(systemName: "stop.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            case .confirming:
                                Image(systemName: "paperplane.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            case .responding:
                                Image(systemName: "checkmark")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            case .error:
                                Image(systemName: "arrow.clockwise")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            default:
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .disabled(manager.currentState == .processing)
                .animation(.easeInOut(duration: 0.2), value: manager.currentState)

                // Status text
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var micButtonColor: Color {
        switch manager.currentState {
        case .idle:
            return .blue
        case .listening:
            return .red
        case .confirming:
            return .orange
        case .processing:
            return .gray
        case .responding:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch manager.currentState {
        case .idle:
            if manager.glassesConnected {
                return "Long-press left TouchBar or tap mic button"
            } else {
                return "Tap mic button to speak (glasses disconnected)"
            }
        case .listening:
            if manager.currentTranscriptionSource == .g2Conversate {
                return "Listening via G2 glasses… speak naturally"
            } else {
                return "Listening via phone mic… tap when done"
            }
        case .confirming:
            if manager.glassesConnected {
                return "Tap glasses to send or double-tap to cancel"
            } else {
                return "Tap mic button to send"
            }
        case .processing:
            return "Processing…"
        case .responding:
            if manager.glassesConnected {
                return "Tap glasses to scroll or double-tap to dismiss"
            } else {
                return "Response ready - tap mic to continue"
            }
        case .error:
            return "Error - tap to retry"
        }
    }
    
    private var transcriptionSourceText: String {
        switch manager.currentTranscriptionSource {
        case .g2Conversate:
            return "G2 glasses"
        case .phoneMic:
            return "phone mic"
        }
    }
    
    private var transcriptionSourceColor: Color {
        switch manager.currentTranscriptionSource {
        case .g2Conversate:
            return .green
        case .phoneMic:
            return .blue
        }
    }
    
    private var stateDisplayText: String {
        switch manager.currentState {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening"
        case .confirming:
            return "Confirm"
        case .processing:
            return "Thinking"
        case .responding:
            return "Response"
        case .error:
            return "Error"
        }
    }
    
    private var stateColor: Color {
        switch manager.currentState {
        case .idle:
            return .primary
        case .listening:
            return .blue
        case .confirming:
            return .orange
        case .processing:
            return .purple
        case .responding:
            return .green
        case .error:
            return .red
        }
    }
}

// MARK: - Status Dot

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
