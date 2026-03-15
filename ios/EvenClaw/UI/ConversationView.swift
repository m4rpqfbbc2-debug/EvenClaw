// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationView.swift
// Terminal-style chat history with G2 status bar and HUD badge.

import SwiftUI

struct ConversationView: View {
    @ObservedObject var stateMachine: AppStateMachine
    let g2Connected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // G2 status bar at top
            g2StatusBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(stateMachine.responseHistory.enumerated()), id: \.offset) { index, exchange in
                            VStack(alignment: .leading, spacing: 6) {
                                // User message
                                HStack(alignment: .top, spacing: 8) {
                                    Text("YOU >")
                                        .font(MatrixTheme.fontTerminal)
                                        .foregroundStyle(MatrixTheme.amber)
                                    Text(exchange.user)
                                        .font(MatrixTheme.fontTerminal)
                                        .foregroundStyle(MatrixTheme.amber)
                                }

                                // Assistant response
                                HStack(alignment: .top, spacing: 8) {
                                    Text("AISHA >")
                                        .font(MatrixTheme.fontTerminal)
                                        .foregroundStyle(MatrixTheme.primary)
                                    Text(exchange.assistant)
                                        .font(MatrixTheme.fontTerminal)
                                        .foregroundStyle(MatrixTheme.primary)
                                }

                                // HUD mirror indicator
                                if g2Connected {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eyeglasses")
                                            .font(.system(size: 9))
                                        Text("on HUD")
                                            .font(MatrixTheme.mono(9))
                                    }
                                    .foregroundStyle(MatrixTheme.dim)
                                }

                                // Separator
                                Rectangle()
                                    .fill(MatrixTheme.dim)
                                    .frame(height: 1)
                            }
                            .id(index)
                        }

                        // Current state indicator
                        currentStateView
                            .id("current")
                    }
                    .padding()
                }
                .onChange(of: stateMachine.responseHistory.count) {
                    withAnimation {
                        proxy.scrollTo("current", anchor: .bottom)
                    }
                }
                .onChange(of: stateMachine.responseCharsVisible) { _, _ in
                    proxy.scrollTo("current", anchor: .bottom)
                }
            }
        }
        .background(MatrixTheme.background)
    }

    // MARK: - G2 Status Bar

    private var g2StatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(g2Connected ? MatrixTheme.success : MatrixTheme.amber)
                .frame(width: 6, height: 6)

            Image(systemName: "eyeglasses")
                .font(.system(size: 11))
                .foregroundStyle(g2Connected ? MatrixTheme.success : MatrixTheme.amber)

            Text(g2Connected ? "G2 CONNECTED" : "G2 DISCONNECTED")
                .font(MatrixTheme.mono(10))
                .foregroundStyle(g2Connected ? MatrixTheme.success : MatrixTheme.amber)

            if g2Connected {
                Spacer()

                Text("HUD ACTIVE")
                    .font(MatrixTheme.mono(9, weight: .bold))
                    .foregroundStyle(MatrixTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Rectangle()
                            .stroke(MatrixTheme.success.opacity(0.5), lineWidth: 1)
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(MatrixTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(MatrixTheme.dim),
            alignment: .bottom
        )
    }

    // MARK: - Current State

    @ViewBuilder
    private var currentStateView: some View {
        switch stateMachine.state {
        case .listening:
            HStack(spacing: 8) {
                Circle()
                    .fill(MatrixTheme.error)
                    .frame(width: 8, height: 8)
                Text("\u{25CF} REC")
                    .font(MatrixTheme.fontTerminal)
                    .foregroundStyle(MatrixTheme.error)
                WaveformView(levels: stateMachine.waveformLevels)
                    .frame(width: 80, height: 24)
            }

        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(MatrixTheme.primary)
                    .scaleEffect(0.7)
                if !stateMachine.currentTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOU > \(stateMachine.currentTranscript)")
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.amber)
                        Text("Processing...")
                            .font(MatrixTheme.fontCaption)
                            .foregroundStyle(MatrixTheme.dim)
                    }
                } else {
                    Text("Processing...")
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.dim)
                }
            }

        case .response:
            VStack(alignment: .leading, spacing: 6) {
                if !stateMachine.currentTranscript.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("YOU >")
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.amber)
                        Text(stateMachine.currentTranscript)
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.amber)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("AISHA >")
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary)
                    let visible = String(stateMachine.currentResponse.prefix(stateMachine.responseCharsVisible))
                    let cursor = stateMachine.responseCharsVisible < stateMachine.currentResponse.count ? "\u{258C}" : ""
                    Text(visible + cursor)
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary)
                }
            }

        case .conversationReady:
            Text(g2Connected
                 ? "\u{25B8} SLIDE TO SPEAK / TAP TO END"
                 : "\u{25B8} TAP MIC TO CONTINUE")
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.dim)

        case .idle:
            if stateMachine.responseHistory.isEmpty {
                VStack(spacing: 12) {
                    G2GlassesIcon(size: 48, connected: g2Connected)

                    Text(g2Connected
                         ? "SLIDE FORWARD TO START"
                         : "TAP MIC TO START")
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else {
                EmptyView()
            }
        }
    }
}
