// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationManager.swift
// Manages chat history (10 turns), response history for scroll-back,
// and conversation logging for cross-channel context.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Conversation")

@MainActor
final class ConversationManager: ObservableObject {

    // MARK: - Constants

    static let maxHistory = 10

    // MARK: - Published

    @Published private(set) var chatHistory: [AIMessage] = []
    @Published private(set) var responseHistory: [(user: String, assistant: String)] = []
    @Published private(set) var responseHistoryIndex = -1

    // MARK: - Public API

    func addUserMessage(_ text: String) {
        chatHistory.append(AIMessage(role: "user", content: text))
        trimHistory()
        log.debug("User message added (history: \(self.chatHistory.count) turns)")
    }

    func addAssistantMessage(_ text: String, userPrompt: String) {
        chatHistory.append(AIMessage(role: "assistant", content: text))
        trimHistory()

        responseHistory.append((user: userPrompt, assistant: text))
        responseHistoryIndex = -1

        log.debug("Assistant response added (response history: \(self.responseHistory.count))")
    }

    func previousExchange() -> (user: String, assistant: String)? {
        guard responseHistoryIndex < responseHistory.count - 1 else { return nil }
        responseHistoryIndex += 1
        return responseHistory[responseHistory.count - 1 - responseHistoryIndex]
    }

    func resetHistoryIndex() {
        responseHistoryIndex = -1
    }

    func clearAll() {
        chatHistory.removeAll()
        responseHistory.removeAll()
        responseHistoryIndex = -1
        log.info("Conversation cleared")
    }

    // MARK: - Private

    private func trimHistory() {
        if chatHistory.count > Self.maxHistory {
            chatHistory.removeFirst(chatHistory.count - Self.maxHistory)
        }
    }
}
