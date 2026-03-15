// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationView.swift
// Terminal-style chat history display.

import SwiftUI

struct ConversationView: View {
    @ObservedObject var stateMachine: AppStateMachine

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stateMachine.responseHistory.enumerated()), id: \.offset) { index, exchange in
                        VStack(alignment: .leading, spacing: 6) {
                            // User message
                            HStack(alignment: .top, spacing: 8) {
                                Text(">")
                                    .font(MatrixTheme.fontTerminal)
                                    .foregroundStyle(MatrixTheme.amber)
                                Text(exchange.user)
                                    .font(MatrixTheme.fontTerminal)
                                    .foregroundStyle(MatrixTheme.amber)
                            }

                            // Assistant response
                            HStack(alignment: .top, spacing: 8) {
                                Text("AISHA:")
                                    .font(MatrixTheme.fontTerminal)
                                    .foregroundStyle(MatrixTheme.primary)
                                Text(exchange.assistant)
                                    .font(MatrixTheme.fontTerminal)
                                    .foregroundStyle(MatrixTheme.primary)
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
        }
        .background(MatrixTheme.background)
    }

    @ViewBuilder
    private var currentStateView: some View {
        switch stateMachine.state {
        case .listening:
            HStack(spacing: 8) {
                Circle()
                    .fill(MatrixTheme.error)
                    .frame(width: 8, height: 8)
                Text("REC")
                    .font(MatrixTheme.fontTerminal)
                    .foregroundStyle(MatrixTheme.error)
                WaveformView(levels: stateMachine.waveformLevels)
            }

        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(MatrixTheme.primary)
                    .scaleEffect(0.7)
                if !stateMachine.currentTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("> \(stateMachine.currentTranscript)")
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
                        Text(">")
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.amber)
                        Text(stateMachine.currentTranscript)
                            .font(MatrixTheme.fontTerminal)
                            .foregroundStyle(MatrixTheme.amber)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("AISHA:")
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary)
                    let visible = String(stateMachine.currentResponse.prefix(stateMachine.responseCharsVisible))
                    let cursor = stateMachine.responseCharsVisible < stateMachine.currentResponse.count ? "▌" : ""
                    Text(visible + cursor)
                        .font(MatrixTheme.fontTerminal)
                        .foregroundStyle(MatrixTheme.primary)
                }
            }

        case .conversationReady:
            Text("▸ SLIDE TO SPEAK / TAP TO END")
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.dim)

        case .idle:
            EmptyView()
        }
    }
}
