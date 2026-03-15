// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// SettingsView.swift
// Grouped settings panel.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var stateMachine: AppStateMachine
    @State private var showSetup = false
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack {
                        Text("SETTINGS")
                            .font(MatrixTheme.fontHeading)
                            .foregroundStyle(MatrixTheme.primary)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Text("DONE")
                                .font(MatrixTheme.mono(14, weight: .semibold))
                                .foregroundStyle(MatrixTheme.primary)
                        }
                    }
                    .padding(.top)

                    // Connection section
                    settingsSection("CONNECTION") {
                        settingsRow("G2 Status", value: stateMachine.isConnected ? "Connected" : "Disconnected")

                        if stateMachine.isConnected {
                            Button {
                                stateMachine.disconnectGlasses()
                            } label: {
                                Text("DISCONNECT")
                                    .matrixOutlineButton()
                            }
                        } else {
                            Button {
                                Task { await stateMachine.connectGlasses() }
                            } label: {
                                Text("CONNECT G2")
                                    .matrixButton()
                            }
                        }
                    }

                    // AI Provider section
                    settingsSection("AI PROVIDER") {
                        let providerName = KeychainManager.load(.selectedProvider) ?? "Not configured"
                        settingsRow("Provider", value: providerName)

                        Button {
                            showSetup = true
                        } label: {
                            Text("CONFIGURE PROVIDER")
                                .matrixOutlineButton()
                        }
                    }

                    // App section
                    settingsSection("APP") {
                        settingsRow("Version", value: "1.0")
                        settingsRow("Build", value: "EvenClaw iOS v1.0")
                        settingsRow("By", value: "Aisha & Gregg — XGX.ai")
                    }

                    // Danger zone
                    settingsSection("DATA") {
                        Button {
                            showClearConfirm = true
                        } label: {
                            Text("CLEAR ALL CREDENTIALS")
                                .font(MatrixTheme.mono(12, weight: .semibold))
                                .foregroundStyle(MatrixTheme.error)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .overlay(
                                    Rectangle()
                                        .stroke(MatrixTheme.error, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }

            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showSetup) {
            SetupView { provider in
                if let provider {
                    stateMachine.setAIProvider(provider)
                }
            }
        }
        .alert("Clear All Credentials?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                KeychainManager.deleteAll()
            }
        } message: {
            Text("This will remove all saved API keys and provider settings from Keychain.")
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .background(MatrixTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(MatrixTheme.border, lineWidth: 1)
            )
        }
    }

    private func settingsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.dim)
            Spacer()
            Text(value)
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.primary)
        }
    }
}
