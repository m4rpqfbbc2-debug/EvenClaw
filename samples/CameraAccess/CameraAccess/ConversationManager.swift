// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationManager.swift
// Q&A flow orchestration, conversation history, and HUD display routing.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Conversation")

@MainActor
class ConversationManager {

    // MARK: - Dependencies

    private weak var sniffer: G2Sniffer?
    private let conversationLogger = ConversationLogger()

    // MARK: - Init

    init(sniffer: G2Sniffer) {
        self.sniffer = sniffer
    }

    // MARK: - Ask OpenClaw

    func askOpenClaw(_ question: String) async {
        guard let sniffer else { return }

        await sniffer.sendQuestion(question)

        sniffer.statusMessage = "Asking OpenClaw..."
        sniffer.isProcessing = true

        let bridge = OpenClawBridge()
        let result = await bridge.sendMessage(question)

        sniffer.isProcessing = false

        if result.success {
            await sniffer.sendReply(result.response)
            sniffer.statusMessage = "Answer displayed on HUD ✨"
            conversationLogger.log(
                userMessage: question,
                aiResponse: result.response,
                provider: "OpenClaw"
            )
        } else {
            let errorMsg = "Error: \(result.response)"
            await sniffer.sendReply(errorMsg)
            sniffer.statusMessage = errorMsg
            log.error("OpenClaw error: \(result.response)")

            // Show user-facing error on HUD
            if result.response.contains("timeout") || result.response.contains("Timeout") {
                await sniffer.sendReply("AI UNAVAILABLE — request timed out")
            }
        }
    }

    // MARK: - Double-Tap Dismiss

    func handleDoubleTapDismiss() {
        guard let sniffer else { return }

        Task {
            if sniffer.evenAIActive {
                await sniffer.exitEvenAIMode()
                try? await Task.sleep(nanoseconds: 200_000_000)
                await sniffer.enterEvenAIMode()
            }
        }

        sniffer.lastAnswer = ""
        sniffer.lastQuestion = ""
        sniffer.isProcessing = false
        sniffer.isListening = false

        sniffer.voiceCommandManager?.cancelCurrentOperation()

        sniffer.statusMessage = "Ready. Say 'Hey Aisha' or hold to talk"

        log.info("Double-tap dismiss complete — ready for next conversation")
    }
}
