// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// Main app entry point — matrix/phosphor UI

import SwiftUI

@main
struct EvenClawApp: App {
    @StateObject private var sniffer = G2Sniffer()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // Migrate any old UserDefaults credentials to Keychain (one-time)
        KeychainManager.migrateFromUserDefaults()

        // Global appearance overrides for matrix theme
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            if !EvenClawConfig.isProviderConfigured {
                SetupView(onComplete: {})
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            } else {
                MainView(sniffer: sniffer)
            }
        }
    }

    private func configureAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(MatrixColor.terminal)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(MatrixColor.phosphor),
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(MatrixColor.phosphor),
            .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(MatrixColor.phosphor)
    }
}

// MARK: - Legacy helper views (used by MainView and debug views)

struct PacketRow: View {
    let entry: PacketLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(entry.timestamp)
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.dimPhosphor)
                Text(entry.direction)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.direction == "RX" ? MatrixColor.phosphor : MatrixColor.amber)
                Text(entry.serviceLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.isConversate ? MatrixColor.phosphor : MatrixColor.dimPhosphor)
                Spacer()
                Text("\(entry.size)B")
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.5))
            }
            Text(entry.hexDump)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.4))
                .lineLimit(2)
            if let parsed = entry.parsedContent {
                Text(parsed)
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.phosphor)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusDot: View {
    let label: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 3) {
            MatrixStatusDot(isActive: isConnected)
            Text(label)
                .font(MatrixFont.micro)
                .foregroundStyle(MatrixColor.dimPhosphor)
        }
    }
}
