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

                Spacer()

                // Transcription
                if !manager.lastTranscription.isEmpty {
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
                if manager.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Processing…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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

                        if manager.isProcessing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: manager.isListening ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(manager.isProcessing)
                .animation(.easeInOut(duration: 0.2), value: manager.isListening)

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
        if manager.isProcessing { return .gray }
        if manager.isListening { return .red }
        return .blue
    }

    private var statusText: String {
        if manager.isProcessing { return "Processing…" }
        if manager.isListening { return "Listening… tap to stop" }
        return "Tap to speak"
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
