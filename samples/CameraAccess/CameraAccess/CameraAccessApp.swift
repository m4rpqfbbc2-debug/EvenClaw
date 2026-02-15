// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

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

struct MainView: View {
    @ObservedObject var manager: VoiceCommandManager
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            Text("EvenClaw")
                .font(.largeTitle.bold())

            // Status dots
            HStack(spacing: 20) {
                StatusDot(label: "OpenClaw", isConnected: manager.openClawConnected)
                StatusDot(label: "Glasses", isConnected: manager.glassesConnected)
            }

            // Debug
            if !manager.debugStatus.isEmpty {
                Text(manager.debugStatus)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Live text / response
            if !manager.liveText.isEmpty && manager.state == .listening {
                Text(manager.liveText)
                    .font(.body)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if !manager.responseText.isEmpty && manager.state == .idle {
                Text(manager.responseText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineLimit(8)
            }

            if case .error(let msg) = manager.state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Mic button
            Button { manager.toggleMic() } label: {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: buttonIcon)
                            .font(.title)
                            .foregroundStyle(.white)
                    }
            }
            .disabled(manager.state == .sending)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gear")
                    .padding()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var buttonColor: Color {
        switch manager.state {
        case .idle: return .blue
        case .listening: return .red
        case .sending: return .purple
        case .error: return .orange
        }
    }

    private var buttonIcon: String {
        switch manager.state {
        case .idle, .error: return "mic.fill"
        case .listening: return "stop.fill"
        case .sending: return "ellipsis"
        }
    }

    private var statusText: String {
        switch manager.state {
        case .idle: return "Tap to speak"
        case .listening: return "Listening... tap to send"
        case .sending: return "Thinking..."
        case .error: return "Tap to try again"
        }
    }
}

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
