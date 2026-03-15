// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// MainView.swift
// Primary interface — dark, minimal, terminal aesthetic.

import SwiftUI

struct MainView: View {
    @ObservedObject var stateMachine: AppStateMachine
    @State private var showSettings = false

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerBar

                // Connection status
                connectionBar

                // Main content
                if stateMachine.isConnected {
                    ConversationView(stateMachine: stateMachine)
                } else {
                    disconnectedView
                }

                // Status bar
                statusBar
            }

            // Scanline overlay
            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(stateMachine: stateMachine)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            GlowingText(text: "EVENCLAW", font: MatrixTheme.fontHeading)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(MatrixTheme.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(MatrixTheme.surface)
    }

    // MARK: - Connection

    private var connectionBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateMachine.isConnected ? MatrixTheme.success : MatrixTheme.error)
                .frame(width: 6, height: 6)

            Text(stateMachine.isConnected ? "G2 CONNECTED" : "G2 DISCONNECTED")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(stateMachine.isConnected ? MatrixTheme.dim : MatrixTheme.error)

            Spacer()

            Text(stateMachine.state.rawValue)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(MatrixTheme.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .bottom
        )
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "eyeglasses")
                .font(.system(size: 48))
                .foregroundStyle(MatrixTheme.dim)

            Text("EVEN G2 NOT CONNECTED")
                .font(MatrixTheme.fontHeading)
                .foregroundStyle(MatrixTheme.dim)

            Text("Ensure your G2 glasses are paired\nvia iOS Bluetooth settings")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
                .multilineTextAlignment(.center)

            Button {
                Task { await stateMachine.connectGlasses() }
            } label: {
                Text("CONNECT")
                    .matrixButton()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(stateMachine.statusText)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
                .lineLimit(1)

            Spacer()

            if stateMachine.state == .listening {
                WaveformView(levels: stateMachine.waveformLevels)
                    .frame(width: 60, height: 20)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(MatrixTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .top
        )
    }
}
