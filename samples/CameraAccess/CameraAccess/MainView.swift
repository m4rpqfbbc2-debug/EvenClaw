// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// MainView.swift
// Primary UI — matrix/phosphor terminal aesthetic.
// Clean dark background, connection status, waveform, conversation history.

import SwiftUI

struct MainView: View {
    @ObservedObject var sniffer: G2Sniffer
    @State private var showSettings = false
    @State private var messageText = ""
    @State private var conversationMessages: [ConversationMessage] = []
    @State private var responseDismissed = false
    @State private var lastTrackedQuestion = ""
    @State private var lastTrackedAnswer = ""
    @State private var typewriterText = ""
    @State private var typewriterComplete = false
    @State private var showBootSequence = true
    @State private var bootFrame = 0

    // Typewriter timer
    private let typewriterTimer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()
    private let bootTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background
            MatrixColor.terminal
                .ignoresSafeArea()
                .scanlines(spacing: 2, opacity: 0.05)

            VStack(spacing: 0) {
                // Header bar
                headerBar

                // Connection status strip
                connectionStrip

                // Main content area
                ZStack {
                    if showBootSequence {
                        bootSequenceView
                    } else {
                        VStack(spacing: 0) {
                            // Conversation history
                            ConversationView(
                                messages: conversationMessages,
                                isTyping: sniffer.isProcessing,
                                typingText: ""
                            )

                            // Waveform (only during recording)
                            if sniffer.isListening {
                                waveformSection
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            // Typewriter response
                            if !sniffer.lastAnswer.isEmpty && !responseDismissed && !sniffer.isProcessing {
                                typewriterSection
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }

                            // Input bar
                            inputBar
                        }
                        .animation(.easeInOut(duration: 0.3), value: sniffer.isListening)
                        .animation(.easeInOut(duration: 0.3), value: sniffer.isProcessing)
                        .animation(.easeInOut(duration: 0.3), value: sniffer.lastAnswer.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await sniffer.requestSpeechPermission()
            await sniffer.connectAndAuth()
            // End boot sequence after connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showBootSequence = false
                }
            }
        }
        // Track new questions
        .onChange(of: sniffer.lastQuestion) { newQ in
            guard !newQ.isEmpty, newQ != lastTrackedQuestion else { return }
            lastTrackedQuestion = newQ
            conversationMessages.append(ConversationMessage(
                role: .user, text: newQ, timestamp: Date()
            ))
            responseDismissed = false
            typewriterText = ""
            typewriterComplete = false
        }
        // Track new answers
        .onChange(of: sniffer.lastAnswer) { newA in
            guard !newA.isEmpty, newA != lastTrackedAnswer else { return }
            lastTrackedAnswer = newA
            responseDismissed = false
            typewriterText = ""
            typewriterComplete = false
        }
        // Typewriter effect for response
        .onReceive(typewriterTimer) { _ in
            guard !sniffer.lastAnswer.isEmpty,
                  !responseDismissed,
                  !typewriterComplete else { return }
            let target = sniffer.lastAnswer
            if typewriterText.count < target.count {
                let nextCount = min(typewriterText.count + 2, target.count)
                typewriterText = String(target.prefix(nextCount))
            } else {
                typewriterComplete = true
            }
        }
        // Boot sequence animation
        .onReceive(bootTimer) { _ in
            guard showBootSequence, bootFrame < HUDFormatter.bootLines.count else { return }
            bootFrame += 1
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text("EVENCLAW")
                .font(MatrixFont.heading)
                .foregroundStyle(MatrixColor.phosphor)
                .phosphorGlow(color: MatrixColor.phosphor, radius: 6, intensity: 0.4)

            Spacer()

            if sniffer.evenAIActive {
                Text("AI MODE")
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.amber)
                    .phosphorGlow(color: MatrixColor.amber, radius: 4, intensity: 0.3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(MatrixColor.amber.opacity(0.3), lineWidth: 1)
                    )
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(MatrixColor.dimPhosphor)
            }
        }
        .padding(.horizontal, MatrixSpacing.md)
        .padding(.top, MatrixSpacing.sm)
        .padding(.bottom, MatrixSpacing.xs)
    }

    // MARK: - Connection Strip

    private var connectionStrip: some View {
        HStack(spacing: MatrixSpacing.md) {
            // G2 connection status
            HStack(spacing: MatrixSpacing.xs) {
                MatrixStatusDot(isActive: sniffer.bleConnected && sniffer.authenticated)
                Text(sniffer.bleConnected && sniffer.authenticated ? "G2 CONNECTED" : "G2 OFFLINE")
                    .font(MatrixFont.micro)
                    .foregroundStyle(sniffer.bleConnected ? MatrixColor.phosphor : MatrixColor.dimPhosphor.opacity(0.4))
            }

            // OpenClaw status
            HStack(spacing: MatrixSpacing.xs) {
                MatrixStatusDot(isActive: sniffer.openClawConnected, activeColor: MatrixColor.amber)
                Text("OPENCLAW")
                    .font(MatrixFont.micro)
                    .foregroundStyle(sniffer.openClawConnected ? MatrixColor.amber : MatrixColor.dimPhosphor.opacity(0.4))
            }

            // App state
            HStack(spacing: MatrixSpacing.xs) {
                MatrixStatusDot(isActive: sniffer.appState.state != .idle,
                                activeColor: sniffer.appState.state == .listening ? MatrixColor.phosphor : MatrixColor.amber)
                Text(sniffer.appState.state.rawValue.uppercased())
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.dimPhosphor)
            }

            // Wake word (optional)
            if sniffer.wakeWordActive {
                HStack(spacing: MatrixSpacing.xs) {
                    MatrixStatusDot(isActive: true)
                    Text("WAKE")
                        .font(MatrixFont.micro)
                        .foregroundStyle(MatrixColor.dimPhosphor)
                }
            }

            Spacer()

            // Mic status
            Text(cleanMicStatus(sniffer.micStatus))
                .font(MatrixFont.micro)
                .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, MatrixSpacing.md)
        .padding(.vertical, MatrixSpacing.xs + 2)
        .background(MatrixColor.darkGreen.opacity(0.15))
    }

    // MARK: - Boot Sequence

    private var bootSequenceView: some View {
        VStack {
            Spacer()
            Text(HUDFormatter.bootFrame(bootFrame))
                .font(MatrixFont.heading)
                .foregroundStyle(MatrixColor.phosphor)
                .phosphorGlow(color: MatrixColor.phosphor, radius: 10, intensity: 0.5)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        VStack(spacing: MatrixSpacing.xs) {
            WaveformView(
                levels: sniffer.audioLevelHistory,
                isActive: sniffer.isListening,
                barCount: 30,
                barSpacing: 2,
                minBarHeight: 3,
                maxBarHeight: 36,
                barColor: MatrixColor.phosphor
            )
            .padding(.horizontal, MatrixSpacing.md)

            if !sniffer.liveTranscript.isEmpty {
                Text(sniffer.liveTranscript)
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.phosphor.opacity(0.7))
                    .lineLimit(2)
                    .padding(.horizontal, MatrixSpacing.md)
            }

            Text("REC")
                .font(MatrixFont.micro)
                .foregroundStyle(MatrixColor.errorRed)
                .phosphorGlow(color: MatrixColor.errorRed, radius: 4, intensity: 0.5)
        }
        .padding(.vertical, MatrixSpacing.sm)
        .background(MatrixColor.darkGreen.opacity(0.1))
    }

    // MARK: - Typewriter Response Section

    private var typewriterSection: some View {
        VStack(alignment: .leading, spacing: MatrixSpacing.sm) {
            HStack(spacing: MatrixSpacing.sm) {
                MatrixStatusDot(isActive: true)
                Text("AISHA >")
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.phosphor)
                    .phosphorGlow(color: MatrixColor.phosphor, radius: 4, intensity: 0.3)
                Spacer()
            }

            Text(typewriterText)
                .font(MatrixFont.body)
                .foregroundStyle(MatrixColor.phosphor.opacity(0.9))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !typewriterComplete {
                Rectangle()
                    .fill(MatrixColor.phosphor)
                    .frame(width: 8, height: 14)
            }

            if typewriterComplete {
                Text("double-tap to dismiss | slide \u{2191} to talk")
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(MatrixSpacing.md)
        .terminalCard(border: MatrixColor.phosphor.opacity(0.3))
        .padding(.horizontal, MatrixSpacing.md)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            responseDismissed = true
            // Add to conversation history
            if !sniffer.lastAnswer.isEmpty {
                conversationMessages.append(ConversationMessage(
                    role: .assistant, text: sniffer.lastAnswer, timestamp: Date()
                ))
            }
            // Dismiss through state machine → goes to conversationReady
            sniffer.appState.goConversationReady()
            sniffer.lastAnswer = ""
            sniffer.lastQuestion = ""
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: MatrixSpacing.xs) {
            // Connect button if not connected
            if !sniffer.bleConnected {
                Button {
                    Task { await sniffer.connectAndAuth() }
                } label: {
                    Text("[ CONNECT G2 ]")
                        .font(MatrixFont.caption)
                        .foregroundStyle(MatrixColor.phosphor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MatrixSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(MatrixColor.phosphor.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.horizontal, MatrixSpacing.md)
            }

            HStack(spacing: MatrixSpacing.sm) {
                // Text input
                TextField("", text: $messageText, prompt: Text("> ask aisha...").foregroundStyle(MatrixColor.dimPhosphor.opacity(0.3)))
                    .font(MatrixFont.body)
                    .foregroundStyle(MatrixColor.phosphor)
                    .tint(MatrixColor.phosphor)
                    .padding(.horizontal, MatrixSpacing.sm)
                    .padding(.vertical, MatrixSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MatrixColor.darkGreen.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(MatrixColor.darkGreen.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }

                // Hold-to-record mic
                Image(systemName: sniffer.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(sniffer.isListening ? MatrixColor.terminal : MatrixColor.phosphor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(sniffer.isListening
                                ? MatrixColor.phosphor
                                : MatrixColor.darkGreen.opacity(0.3))
                            .scaleEffect(sniffer.isListening
                                ? 1.0 + CGFloat(sniffer.audioLevel * 2)
                                : 1.0)
                            .animation(.easeOut(duration: 0.08), value: sniffer.audioLevel)
                    )
                    .phosphorGlow(color: MatrixColor.phosphor, radius: sniffer.isListening ? 8 : 4, intensity: sniffer.isListening ? 0.6 : 0.2)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.15)
                            .onEnded { _ in
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                sniffer.startListening()
                            }
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { _ in
                                if sniffer.isListening {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    Task { await sniffer.stopListeningAndSend() }
                                }
                            }
                    )

                // Send button
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(messageText.isEmpty ? MatrixColor.dimPhosphor.opacity(0.3) : MatrixColor.terminal)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(messageText.isEmpty ? MatrixColor.darkGreen.opacity(0.2) : MatrixColor.phosphor)
                        )
                }
                .disabled(messageText.isEmpty || !sniffer.authenticated)
            }
            .padding(.horizontal, MatrixSpacing.md)
            .padding(.vertical, MatrixSpacing.sm)
        }
        .background(
            MatrixColor.terminal
                .overlay(
                    Rectangle()
                        .fill(MatrixColor.darkGreen.opacity(0.1))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await sniffer.askOpenClaw(text) }
    }

    /// Strip emojis from mic status for clean monospace display
    private func cleanMicStatus(_ status: String) -> String {
        status.replacingOccurrences(of: "🎙️ ", with: "")
            .replacingOccurrences(of: "⏳ ", with: "")
            .replacingOccurrences(of: "🔵 ", with: "")
            .replacingOccurrences(of: "❌ ", with: "ERR: ")
            .uppercased()
    }
}
