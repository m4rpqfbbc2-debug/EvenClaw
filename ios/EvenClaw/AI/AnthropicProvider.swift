// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AnthropicProvider.swift
// Direct Anthropic Claude API integration.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Anthropic")

final class AnthropicProvider: AIProvider, @unchecked Sendable {

    let name = "Anthropic"
    let modelName: String

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"

    static let availableModels = [
        "claude-sonnet-4-20250514",
        "claude-opus-4-0-20250514",
        "claude-haiku-4-5-20251001",
    ]

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.modelName = model
    }

    convenience init?() {
        guard let key = KeychainManager.load(.anthropicAPIKey),
              !key.isEmpty else { return nil }
        let model = KeychainManager.load(.anthropicModel) ?? Self.availableModels[0]
        self.init(apiKey: key, model: model)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        // Build messages array — Anthropic requires alternating user/assistant
        var messages: [[String: String]] = []
        for msg in history.dropLast() { // history includes current prompt already
            messages.append(["role": msg.role, "content": msg.content])
        }
        // Ensure last message is user
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "system": "You are Aisha's AI assistant running on Even Realities G2 smart glasses via EvenClaw. Keep responses concise — the display shows ~120 characters at a time. Be direct, helpful, and brief.",
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Sending to Anthropic (\(self.modelName))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            log.error("Anthropic error \(httpResponse.statusCode): \(errorText)")
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    func validate() async -> Bool {
        !apiKey.isEmpty && apiKey.hasPrefix("sk-ant-")
    }
}
