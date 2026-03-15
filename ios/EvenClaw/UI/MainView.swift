// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// MainView.swift
// G2-first primary interface. Glasses are the hero — centre screen.
// Phone mic is a small fallback. G2 connection status visible on every state.

import SwiftUI

struct MainView: View {
    @ObservedObject var stateMachine: AppStateMachine
    @ObservedObject var g2Connector: G2AutoConnector
    @State private var showSettings = false
    @State private var showG2Sheet = false
    @State private var showConversation = false

    private var isG2Connected: Bool {
        if case .connected = g2Connector.scanState { return true }
        return false
    }

    private var isScanning: Bool {
        switch g2Connector.scanState {
        case .scanning, .connecting, .reconnecting: return true
        default: return false
        }
    }

    private var hasMessages: Bool {
        !stateMachine.responseHistory.isEmpty || stateMachine.state != .idle
    }

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if hasMessages || showConversation {
                    // Conversation mode — G2 status stays in header
                    ConversationView(stateMachine: stateMachine, g2Connected: isG2Connected)
                    inputControls
                } else {
                    // Hero mode — G2 glasses centre screen
                    Spacer()
                    g2HeroSection
                    Spacer()
                    phoneFallback
                }

                statusBar
            }

            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(stateMachine: stateMachine, g2Connector: g2Connector)
        }
        .sheet(isPresented: $showG2Sheet) {
            G2ConnectionSheet(g2Connector: g2Connector)
        }
        .onChange(of: isG2Connected) { _, connected in
            if connected && !hasMessages {
                // Brief delay to show "G2 CONNECTED" before transitioning
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showConversation = true
                        }
                    }
                }
            }
        }
        .onChange(of: stateMachine.state) { _, newState in
            if newState == .listening || newState == .processing || newState == .response {
                showConversation = true
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            GlowingText(text: "EVENCLAW", font: MatrixTheme.fontHeading)

            Spacer()

            // G2 status indicator — always visible
            Button {
                showG2Sheet = true
            } label: {
                G2StatusIndicator(scanState: g2Connector.scanState)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(MatrixTheme.primary)
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(MatrixTheme.surface)
    }

    // MARK: - G2 Hero Section (centre of screen)

    private var g2HeroSection: some View {
        VStack(spacing: 24) {
            ZStack {
                // Scanning pulse rings
                if isScanning {
                    ScanningPulse()
                    ScanningPulse()
                        .rotationEffect(.degrees(60))
                }

                // THE hero glasses icon
                G2GlassesIcon(size: 96, connected: isG2Connected)
            }

            // Status text below icon
            if isG2Connected {
                VStack(spacing: 8) {
                    Text("G2 CONNECTED")
                        .font(MatrixTheme.mono(16, weight: .bold))
                        .foregroundStyle(MatrixTheme.success)

                    Text("SLIDE FORWARD TO START")
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary.opacity(0.7))
                }
            } else if isScanning {
                VStack(spacing: 8) {
                    Text("SCANNING FOR G2...")
                        .font(MatrixTheme.mono(14, weight: .semibold))
                        .foregroundStyle(MatrixTheme.primary)

                    Text("SEARCHING...")
                        .font(MatrixTheme.fontCaption)
                        .foregroundStyle(MatrixTheme.dim)
                }
            } else {
                VStack(spacing: 8) {
                    Text(scanStateLabel)
                        .font(MatrixTheme.mono(14, weight: .semibold))
                        .foregroundStyle(scanStateColor)

                    Button {
                        g2Connector.retryNow()
                    } label: {
                        Text("TAP TO SCAN")
                            .font(MatrixTheme.fontCaption)
                            .foregroundStyle(MatrixTheme.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .overlay(
                                Rectangle()
                                    .stroke(MatrixTheme.primary, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var scanStateLabel: String {
        switch g2Connector.scanState {
        case .idle: return "G2 NOT CONNECTED"
        case .bluetoothOff: return "BLUETOOTH OFF"
        case .unauthorized: return "BLUETOOTH PERMISSION NEEDED"
        default: return "G2 NOT CONNECTED"
        }
    }

    private var scanStateColor: Color {
        switch g2Connector.scanState {
        case .bluetoothOff, .unauthorized: return MatrixTheme.error
        default: return MatrixTheme.dim
        }
    }

    // MARK: - Phone Fallback (small, secondary)

    private var phoneFallback: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(MatrixTheme.dim)
                .frame(height: 1)

            Text("No glasses? Use phone mic instead")
                .font(MatrixTheme.mono(10))
                .foregroundStyle(MatrixTheme.dim)

            Button {
                showConversation = true
                stateMachine.phoneMicActivate()
            } label: {
                ZStack {
                    Circle()
                        .stroke(MatrixTheme.dim, lineWidth: 1)
                        .frame(width: 44, height: 44)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(MatrixTheme.dim)
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Input Controls (conversation mode)

    @ViewBuilder
    private var inputControls: some View {
        if stateMachine.glassesAvailable {
            glassesActiveControls
        } else {
            phoneMicControls
        }
    }

    private var phoneMicControls: some View {
        HStack(spacing: 16) {
            Spacer()

            Button {
                if stateMachine.state == .listening {
                    stateMachine.phoneSend()
                } else {
                    stateMachine.phoneMicActivate()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(stateMachine.state == .listening ? MatrixTheme.error : MatrixTheme.primary)
                        .frame(width: 64, height: 64)
                        .shadow(
                            color: (stateMachine.state == .listening ? MatrixTheme.error : MatrixTheme.primary)
                                .opacity(0.6),
                            radius: stateMachine.state == .listening ? 16 : 8
                        )

                    Image(systemName: stateMachine.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(MatrixTheme.background)
                }
            }
            .disabled(stateMachine.state == .processing)

            Spacer()
        }
        .padding(.vertical, 16)
        .background(MatrixTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .top
        )
    }

    private var glassesActiveControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(MatrixTheme.success)
                    .frame(width: 8, height: 8)
                Text("G2 ACTIVE \u{2014} USE GESTURES")
                    .font(MatrixTheme.fontCaption)
                    .foregroundStyle(MatrixTheme.success)
            }

            Text("SLIDE FWD \u{2192} Record  |  2\u{00D7} TAP \u{2192} Send")
                .font(MatrixTheme.mono(10))
                .foregroundStyle(MatrixTheme.dim)

            // Secondary phone mic button (smaller, still available)
            Button {
                if stateMachine.state == .listening {
                    stateMachine.phoneSend()
                } else {
                    stateMachine.phoneMicActivate()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(MatrixTheme.dim, lineWidth: 1)
                        .frame(width: 36, height: 36)

                    Image(systemName: stateMachine.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(MatrixTheme.dim)
                }
            }
            .disabled(stateMachine.state == .processing)
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .background(MatrixTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .top
        )
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(stateMachine.providerName) \u{00B7} \(stateMachine.modelName)")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
                .lineLimit(1)

            Spacer()

            if let time = stateMachine.lastResponseTime {
                Text(String(format: "%.1fs", time))
                    .font(MatrixTheme.fontCaption)
                    .foregroundStyle(MatrixTheme.dim)
            }

            if stateMachine.state == .listening {
                WaveformView(levels: stateMachine.waveformLevels)
                    .frame(width: 60, height: 20)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(MatrixTheme.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .top
        )
    }
}

// MARK: - G2 Status Indicator

struct G2StatusIndicator: View {
    let scanState: G2AutoConnector.ScanState
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 12))
                .foregroundStyle(dotColor)

            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(
                    isScanning
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear { isPulsing = isScanning }
                .onChange(of: isScanning) { _, scanning in isPulsing = scanning }

            Text(label)
                .font(MatrixTheme.mono(10))
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .stroke(dotColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var dotColor: Color {
        switch scanState {
        case .connected: return MatrixTheme.success
        case .scanning, .connecting, .reconnecting: return MatrixTheme.amber
        case .idle: return MatrixTheme.dim
        case .bluetoothOff, .unauthorized: return MatrixTheme.error
        }
    }

    private var label: String {
        switch scanState {
        case .connected: return "G2"
        case .scanning: return "SCAN"
        case .connecting: return "LINK"
        case .reconnecting: return "RETRY"
        case .idle: return "G2"
        case .bluetoothOff: return "BT OFF"
        case .unauthorized: return "BT AUTH"
        }
    }

    private var isScanning: Bool {
        switch scanState {
        case .scanning, .connecting, .reconnecting: return true
        default: return false
        }
    }
}

// MARK: - G2 Connection Sheet

struct G2ConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var g2Connector: G2AutoConnector

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("G2 CONNECTION")
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

                // Status
                HStack(spacing: 12) {
                    G2StatusIndicator(scanState: g2Connector.scanState)
                    Text(statusDescription)
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary)
                }

                if let name = g2Connector.connectedDeviceName {
                    HStack {
                        Text("DEVICE")
                            .font(MatrixTheme.fontCaption)
                            .foregroundStyle(MatrixTheme.dim)
                        Spacer()
                        Text(name)
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.primary)
                    }
                }

                // Actions
                VStack(spacing: 12) {
                    if g2Connector.isConnected {
                        Button {
                            g2Connector.disconnect()
                        } label: {
                            Text("DISCONNECT")
                                .matrixOutlineButton()
                        }
                    } else {
                        Button {
                            g2Connector.retryNow()
                        } label: {
                            Text("SCAN NOW")
                                .matrixButton()
                        }
                    }
                }

                // Troubleshooting
                VStack(alignment: .leading, spacing: 8) {
                    Text("TROUBLESHOOTING")
                        .font(MatrixTheme.fontCaption)
                        .foregroundStyle(MatrixTheme.dim)

                    Text("1. Ensure G2 glasses are powered on\n2. Pair via iOS Settings \u{2192} Bluetooth first\n3. Keep glasses within 3m of phone\n4. If stuck, toggle Bluetooth off/on")
                        .font(MatrixTheme.mono(11))
                        .foregroundStyle(MatrixTheme.dim)
                        .lineSpacing(4)
                }
                .padding()
                .background(MatrixTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(MatrixTheme.border, lineWidth: 1)
                )

                Spacer()
            }
            .padding()

            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var statusDescription: String {
        switch g2Connector.scanState {
        case .idle: return "Not scanning"
        case .scanning: return "Searching for G2 glasses..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting (attempt \(attempt))..."
        case .bluetoothOff: return "Bluetooth is turned off"
        case .unauthorized: return "Bluetooth permission needed"
        }
    }
}
