// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OpenClawBridge.swift
// Routes messages through the active AI provider.

import Foundation

enum OpenClawConnectionState: Equatable {
    case notConfigured
    case checking
    case connected
    case unreachable(String)
}

@MainActor
class OpenClawBridge: ObservableObject {
    @Published var connectionState: OpenClawConnectionState = .notConfigured

    private var conversationHistory: [[String: String]] = []
    private let maxHistoryTurns = 10

    var baseURL: String {
        let host = EvenClawConfig.openClawHost
        let port = EvenClawConfig.openClawPort
        return "\(host):\(port)"
    }

    func checkConnection() async {
        guard EvenClawConfig.isProviderConfigured else {
            connectionState = .notConfigured; return
        }
        connectionState = .checking

        guard let provider = AIProviderFactory.activeProvider() else {
            connectionState = .notConfigured; return
        }

        let result = await provider.validate()
        if result.valid {
            connectionState = .connected
            NSLog("[OpenClaw] Provider %@ reachable", provider.providerType.displayName)
        } else {
            connectionState = .unreachable(result.error ?? "Unknown error")
            NSLog("[OpenClaw] Provider unreachable: %@", result.error ?? "?")
        }
    }

    func resetSession() {
        conversationHistory = []
    }

    func sendMessage(_ text: String) async -> (success: Bool, response: String) {
        guard let provider = AIProviderFactory.activeProvider() else {
            return (false, "No AI provider configured. Open Settings to set one up.")
        }

        if conversationHistory.count > maxHistoryTurns * 2 {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
        }

        NSLog("[OpenClaw] Sending via %@: %@", provider.providerType.displayName, String(text.prefix(100)))

        let result = await provider.sendMessage(text, history: conversationHistory)

        if result.success {
            conversationHistory.append(["role": "user", "content": text])
            conversationHistory.append(["role": "assistant", "content": result.response])
            NSLog("[OpenClaw] Response: %@", String(result.response.prefix(200)))
        }

        return result
    }
}
