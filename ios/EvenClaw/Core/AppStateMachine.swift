// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AppStateMachine.swift
// Port of reference/app.ts — state machine orchestrating audio, AI, and HUD.
// Glasses-optional: conversation works on phone, HUD mirrors when G2 connected.

import Foundation
import Combine
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "StateMachine")

enum AppState: String, Equatable {
    case idle = "IDLE"
    case listening = "LISTENING"
    case processing = "PROCESSING"
    case response = "RESPONSE"
    case conversationReady = "CONVERSATION_READY"
}

@MainActor
final class AppStateMachine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: AppState = .idle
    @Published private(set) var statusText = ""
    @Published private(set) var currentTranscript = ""
    @Published private(set) var currentResponse = ""
    @Published private(set) var responseCharsVisible = 0
    @Published private(set) var animFrame = 0
    @Published private(set) var waveformLevels: [Float] = Array(repeating: 0, count: 8)
    @Published private(set) var lastResponseTime: TimeInterval?
    @Published var glassesAvailable = false

    // MARK: - Constants (from app.ts)

    private let typewriterSpeedMS: UInt64 = 2          // ~500 chars/sec
    private let conversationTimeoutS: TimeInterval = 60
    private let maxHistory = 10

    // MARK: - Conversation

    private(set) var chatHistory: [(role: String, content: String)] = []
    @Published private(set) var responseHistory: [(user: String, assistant: String)] = []
    private(set) var responseHistoryIndex = -1

    private var inConversation = false
    private var currentResponseText = ""
    private var responseScrollOffset = 0

    // MARK: - Dependencies

    var glasses: EvenG2Provider? {
        didSet {
            guard let glasses else { return }
            glasses.onGesture = { [weak self] gesture in
                Task { @MainActor in
                    self?.handleGesture(gesture)
                }
            }
        }
    }
    private let audioCapture = AudioCaptureManager()
    private let transcription = TranscriptionService()
    private var aiProvider: (any AIProvider)?

    // MARK: - Timers

    private var animationTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?
    private var conversationTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        audioCapture.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.updateWaveform(level)
            }
        }
    }

    // MARK: - Public API

    var providerName: String {
        aiProvider?.name ?? "No provider"
    }

    var modelName: String {
        aiProvider?.modelName ?? "—"
    }

    func setAIProvider(_ provider: any AIProvider) {
        aiProvider = provider
    }

    /// Phone mic button: same as slide-forward on glasses.
    func phoneMicActivate() {
        switch state {
        case .idle:
            inConversation = true
            Task { await startListening() }
        case .conversationReady:
            Task { await startListening() }
        case .response:
            Task { await startListening() }
        default:
            break
        }
    }

    /// Phone send button: same as double-tap on glasses.
    func phoneSend() {
        switch state {
        case .listening:
            audioCapture.forceSend()
        case .response:
            Task { await goConversationReady() }
        case .conversationReady:
            Task { await startListening() }
        default:
            break
        }
    }

    /// Phone dismiss: same as single tap.
    func phoneDismiss() {
        switch state {
        case .response:
            Task { await goConversationReady() }
        case .conversationReady:
            Task { await goIdle() }
        default:
            break
        }
    }

    // MARK: - State Transitions

    private func goIdle() async {
        cancelAllTasks()
        inConversation = false
        chatHistory.removeAll()
        responseHistoryIndex = -1
        state = .idle
        statusText = "TAP MIC TO START"
        currentTranscript = ""
        currentResponse = ""
        responseCharsVisible = 0
        audioCapture.stopRecording()
        await displayOnHUD(" ")
        log.info("→ IDLE")
    }

    private func goConversationReady() async {
        cancelAllTasks()
        state = .conversationReady
        statusText = glassesAvailable
            ? "▸ SLIDE TO SPEAK / TAP TO END"
            : "▸ TAP MIC TO SPEAK"
        audioCapture.stopRecording()
        await displayOnHUD("▸ SLIDE TO SPEAK\n\nTAP TO END")

        conversationTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(conversationTimeoutS))
            guard !Task.isCancelled, self.state == .conversationReady else { return }
            log.info("Conversation timeout (60s)")
            await self.goIdle()
        }
        log.info("→ CONVERSATION_READY")
    }

    private func startListening() async {
        cancelAllTasks()
        state = .listening
        statusText = glassesAvailable
            ? "● REC — DOUBLE TAP TO SEND"
            : "● REC — TAP MIC TO SEND"
        currentTranscript = ""
        currentResponse = ""

        do {
            try await transcription.prepare()
        } catch {
            log.error("Transcription prep failed: \(error.localizedDescription)")
        }

        audioCapture.onRecordingComplete = { [weak self] audioURL in
            Task { @MainActor in
                await self?.handleRecordingDone(audioURL: audioURL)
            }
        }

        audioCapture.startRecording()

        // Animate waveform on HUD
        animFrame = 0
        let waveFrames = [
            "▁▃▅▇▅▃▁",
            "▃▅▇▅▃▁▃",
            "▅▇▅▃▁▃▅",
            "▇▅▃▁▃▅▇"
        ]
        await displayOnHUD("● REC  \(waveFrames[0])\n\nDOUBLE TAP TO SEND")

        animationTask = Task {
            while !Task.isCancelled && self.state == .listening {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                self.animFrame += 1
                let frame = waveFrames[self.animFrame % waveFrames.count]
                await self.displayOnHUD("● REC  \(frame)\n\nDOUBLE TAP TO SEND")
            }
        }

        log.info("→ LISTENING")
    }

    private func handleRecordingDone(audioURL: URL?) async {
        cancelAllTasks()
        state = .processing
        statusText = "Processing..."
        audioCapture.stopRecording()
        let requestStart = Date()

        // Show spinner
        let spinnerFrames = ["◐", "◑", "◒", "◓"]
        animFrame = 0
        await displayOnHUD(spinnerFrames[0])

        animationTask = Task {
            while !Task.isCancelled && self.state == .processing {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { break }
                self.animFrame += 1
                let spinner = spinnerFrames[self.animFrame % spinnerFrames.count]
                if self.currentTranscript.isEmpty {
                    await self.displayOnHUD(spinner)
                } else {
                    await self.displayOnHUD("\"\(self.currentTranscript)\"\n\n\(spinner)")
                }
            }
        }

        // Transcribe
        do {
            let transcript: String
            if let url = audioURL {
                transcript = try await transcription.transcribe(audioURL: url)
            } else {
                transcript = ""
            }

            log.info("Transcript: \(transcript)")
            currentTranscript = transcript

            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.warning("Empty transcript")
                if inConversation {
                    await goConversationReady()
                } else {
                    await goIdle()
                }
                return
            }

            // Add to history
            chatHistory.append((role: "user", content: transcript))
            if chatHistory.count > maxHistory {
                chatHistory.removeFirst(chatHistory.count - maxHistory)
            }

            // Update HUD with transcript
            let spinner = spinnerFrames[animFrame % spinnerFrames.count]
            await displayOnHUD("\"\(transcript)\"\n\n\(spinner)")

            // Send to AI
            guard let provider = aiProvider else {
                log.error("No AI provider configured")
                await displayOnHUD("No AI provider set up")
                try? await Task.sleep(for: .seconds(2))
                if inConversation { await goConversationReady() } else { await goIdle() }
                return
            }

            let history = chatHistory.map { AIMessage(role: $0.role, content: $0.content) }
            let response = try await provider.sendMessage(prompt: transcript, history: history)
            let elapsed = Date().timeIntervalSince(requestStart)
            lastResponseTime = elapsed
            log.info("AI response (\(response.count) chars) in \(String(format: "%.1f", elapsed))s")

            guard !response.isEmpty,
                  response != "No response from AI.",
                  response != "No response received." else {
                await displayOnHUD("No response - try again")
                try? await Task.sleep(for: .seconds(2))
                if inConversation { await goConversationReady() } else { await goIdle() }
                return
            }

            // Add response to history
            chatHistory.append((role: "assistant", content: response))
            if chatHistory.count > maxHistory {
                chatHistory.removeFirst(chatHistory.count - maxHistory)
            }

            // Save to response history
            responseHistory.append((user: transcript, assistant: response))
            responseHistoryIndex = -1

            // Log the exchange
            let providerDesc = String(describing: type(of: provider))
            ConversationLogger.shared.logExchange(user: transcript, assistant: response, provider: providerDesc)

            // Show response with typewriter
            cancelAllTasks()
            await showResponse(response)

        } catch {
            log.error("Processing error: \(error.localizedDescription)")
            await displayOnHUD("Error - try again")
            try? await Task.sleep(for: .seconds(2))
            if inConversation { await goConversationReady() } else { await goIdle() }
        }
    }

    private func showResponse(_ text: String) async {
        cancelAllTasks()
        state = .response
        currentResponseText = text
        currentResponse = text
        responseScrollOffset = 0
        inConversation = true
        statusText = glassesAvailable
            ? "AISHA — tap/double-tap to continue"
            : "AISHA — tap mic for next"

        // Typewriter effect
        typewriterTask = Task {
            for i in 1...text.count {
                guard !Task.isCancelled, self.state == .response else { break }
                self.responseCharsVisible = i
                let visible = String(text.prefix(i))
                let cursor = i < text.count ? "▌" : ""
                await self.displayOnHUD("AISHA:\n\(visible)\(cursor)")
                try? await Task.sleep(for: .milliseconds(self.typewriterSpeedMS))
            }

            // After typewriter, show full scrollable view
            guard !Task.isCancelled, self.state == .response else { return }
            self.responseCharsVisible = text.count
            await self.displayOnHUD("AISHA:\n\(text)")
            log.info("Response displayed — tap to continue")
        }

        log.info("→ RESPONSE")
    }

    // MARK: - Gesture Handling

    private func handleGesture(_ gesture: GlassesGesture) {
        log.info("Gesture: \(String(describing: gesture)) in state: \(self.state.rawValue)")

        switch gesture {

        // SLIDE FORWARD — primary activation
        case .swipeForward:
            switch state {
            case .idle:
                inConversation = true
                Task { await startListening() }
            case .conversationReady:
                Task { await startListening() }
            case .response:
                Task { await startListening() }
            default:
                break
            }

        // SLIDE BACK — scroll response history
        case .swipeBackward:
            if state == .response {
                scrollResponseBack()
            }

        // DOUBLE TAP — send / dismiss
        case .doubleTap:
            switch state {
            case .listening:
                audioCapture.forceSend()
            case .response:
                Task { await goConversationReady() }
            case .conversationReady:
                Task { await startListening() }
            default:
                break
            }

        // SINGLE TAP — dismiss / end
        case .tap:
            switch state {
            case .response:
                Task { await goConversationReady() }
            case .conversationReady:
                Task { await goIdle() }
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Response Scrolling

    private func scrollResponseBack() {
        if responseHistoryIndex < responseHistory.count - 1 {
            responseHistoryIndex += 1
            let prev = responseHistory[responseHistory.count - 1 - responseHistoryIndex]
            let text = "YOU: \(prev.user)\n\nAISHA: \(prev.assistant)"
            currentResponseText = text
            currentResponse = text
            responseCharsVisible = text.count
            Task { await displayOnHUD("AISHA:\n\(text)") }
        }
    }

    // MARK: - HUD Display

    private func displayOnHUD(_ text: String) async {
        guard glassesAvailable, let glasses else { return }
        do {
            try await glasses.displayText(text, style: DisplayStyle())
        } catch {
            log.error("HUD display error: \(error.localizedDescription)")
        }
    }

    // MARK: - Waveform

    private func updateWaveform(_ level: Float) {
        var levels = waveformLevels
        levels.removeFirst()
        levels.append(level)
        waveformLevels = levels
    }

    // MARK: - Cleanup

    private func cancelAllTasks() {
        animationTask?.cancel()
        animationTask = nil
        typewriterTask?.cancel()
        typewriterTask = nil
        conversationTimeoutTask?.cancel()
        conversationTimeoutTask = nil
    }
}
