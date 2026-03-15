// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AppStateMachine.swift
// Central state machine for gesture-driven UX.
// Ported from evenclaw-v5/src/app.ts — proven state machine.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "StateMachine")

// MARK: - App State

enum AppState: String, Equatable {
    case idle               // Mic OFF, clean HUD, slide forward to activate
    case listening          // Mic ON, waveform animation, double-tap to send
    case processing         // Transcript shown, spinner while AI thinks
    case response           // 'AISHA:' tag, typewriter at reading speed, scrollable
    case conversationReady  // Waiting for slide forward or single tap to end
}

// MARK: - State Machine Delegate

@MainActor
protocol AppStateMachineDelegate: AnyObject {
    /// Called on every state transition
    func stateMachine(_ sm: AppStateMachine, didTransitionFrom oldState: AppState, to newState: AppState)

    /// Mic control — enable/disable iPhone mic
    func stateMachineStartMic(_ sm: AppStateMachine)
    func stateMachineStopMic(_ sm: AppStateMachine)

    /// Force-send the current recording (double-tap trigger)
    func stateMachineForceSend(_ sm: AppStateMachine)

    /// HUD display commands
    func stateMachine(_ sm: AppStateMachine, showOnHUD text: String)
    func stateMachine(_ sm: AppStateMachine, showResponseOnHUD text: String)
    func stateMachineClearHUD(_ sm: AppStateMachine)
    func stateMachine(_ sm: AppStateMachine, showConversationReadyHUD text: String)

    /// Send transcript to AI and get response
    func stateMachine(_ sm: AppStateMachine, sendToAI transcript: String) async -> String?
}

// MARK: - App State Machine

@MainActor
class AppStateMachine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: AppState = .idle
    @Published var inConversation = false
    @Published var currentTranscript = ""
    @Published var currentResponseText = ""

    // MARK: - Conversation History

    struct ChatMessage {
        let role: String  // "user" or "assistant"
        let content: String
    }

    struct ResponseExchange {
        let user: String
        let assistant: String
    }

    private(set) var chatHistory: [ChatMessage] = []
    private(set) var responseHistory: [ResponseExchange] = []
    var responseHistoryIndex: Int = -1  // -1 = current, 0+ = older

    private let maxHistory = 10

    // MARK: - Timers

    private var conversationTimeoutTimer: Timer?
    private let conversationTimeoutSeconds: TimeInterval = 60.0

    // MARK: - Delegate

    weak var delegate: AppStateMachineDelegate?

    // MARK: - State Transitions

    func setState(_ newState: AppState) {
        let old = state
        state = newState
        log.info("State: \(old.rawValue) → \(newState.rawValue)")
        delegate?.stateMachine(self, didTransitionFrom: old, to: newState)
    }

    // MARK: - Go Idle

    func goIdle() {
        clearTimers()
        inConversation = false
        chatHistory.removeAll()
        responseHistory.removeAll()
        responseHistoryIndex = -1
        currentTranscript = ""
        currentResponseText = ""
        setState(.idle)
        delegate?.stateMachineStopMic(self)
        delegate?.stateMachineClearHUD(self)
        log.info("Idle — slide forward to activate")
    }

    // MARK: - Go Conversation Ready

    func goConversationReady() {
        clearTimers()
        setState(.conversationReady)
        delegate?.stateMachineStopMic(self)
        delegate?.stateMachine(self, showConversationReadyHUD: "↑ slide to talk • tap to end")

        // Timeout: 60s of no interaction → back to idle
        conversationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: conversationTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .conversationReady else { return }
                log.info("Conversation timeout (60s) — returning to idle")
                self.goIdle()
            }
        }
    }

    // MARK: - Start Listening

    func startListening() {
        clearTimers()
        if !inConversation {
            inConversation = true
        }
        currentTranscript = ""
        setState(.listening)
        delegate?.stateMachineStartMic(self)
        delegate?.stateMachine(self, showOnHUD: "Listening...")
    }

    // MARK: - Handle Recording Done (transcript ready)

    func handleTranscript(_ transcript: String) {
        guard state == .listening else { return }
        currentTranscript = transcript
    }

    // MARK: - Send Recording (double-tap or programmatic)

    func sendRecording() {
        guard state == .listening else { return }
        delegate?.stateMachineForceSend(self)
    }

    // MARK: - Process Transcript → AI → Response

    func processTranscript(_ transcript: String) async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.warning("Empty transcript — returning to conversation or idle")
            if inConversation {
                goConversationReady()
            } else {
                goIdle()
            }
            return
        }

        clearTimers()
        setState(.processing)
        delegate?.stateMachineStopMic(self)

        // Show transcript instantly on HUD while AI thinks
        delegate?.stateMachine(self, showOnHUD: transcript)

        // Add to chat history
        chatHistory.append(ChatMessage(role: "user", content: transcript))
        trimHistory()

        // Send to AI
        log.info("Sending to AI: \(transcript.prefix(80))")
        guard let response = await delegate?.stateMachine(self, sendToAI: transcript) else {
            log.warning("No response from AI")
            delegate?.stateMachine(self, showOnHUD: "No response - try again")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if inConversation {
                goConversationReady()
            } else {
                goIdle()
            }
            return
        }

        // Add response to history
        chatHistory.append(ChatMessage(role: "assistant", content: response))
        trimHistory()

        // Save to response history for scroll-back
        responseHistory.append(ResponseExchange(user: transcript, assistant: response))
        responseHistoryIndex = -1

        // Show response
        showResponse(response)
    }

    // MARK: - Show Response

    private func showResponse(_ text: String) {
        clearTimers()
        setState(.response)
        currentResponseText = text
        delegate?.stateMachine(self, showResponseOnHUD: text)
        log.info("Response displayed — tap to continue, slide back to scroll")
    }

    // MARK: - Scroll Response History (slide back)

    func scrollBack() {
        guard state == .response else { return }

        // Go to previous exchange in history
        if responseHistoryIndex < responseHistory.count - 1 {
            responseHistoryIndex += 1
            let prev = responseHistory[responseHistory.count - 1 - responseHistoryIndex]
            currentResponseText = "YOU: \(prev.user)\n\nAISHA: \(prev.assistant)"
            delegate?.stateMachine(self, showResponseOnHUD: currentResponseText)
            log.info("Previous exchange (\(self.responseHistoryIndex + 1) back)")
        }
    }

    // MARK: - Helpers

    private func clearTimers() {
        conversationTimeoutTimer?.invalidate()
        conversationTimeoutTimer = nil
    }

    private func trimHistory() {
        if chatHistory.count > maxHistory {
            chatHistory.removeFirst(chatHistory.count - maxHistory)
        }
    }
}
