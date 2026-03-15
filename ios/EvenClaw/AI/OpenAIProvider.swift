// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OpenAIProvider.swift
// Direct OpenAI GPT API integration.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "OpenAI")

final class OpenAIProvider: AIProvider, @unchecked Sendable {

    let name = "OpenAI"
    let modelName: String

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    static let availableModels = [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo",
        "o3-mini",
    ]

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.modelName = model
    }

    convenience init?() {
        guard let key = KeychainManager.load(.openAIAPIKey),
              !key.isEmpty else { return nil }
        let model = KeychainManager.load(.openAIModel) ?? Self.availableModels[0]
        self.init(apiKey: key, model: model)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are Aisha's AI assistant running on Even Realities G2 smart glasses via EvenClaw. Keep responses concise — the display shows ~120 characters at a time. Be direct, helpful, and brief."]
        ]
        for msg in history.dropLast() {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Sending to OpenAI (\(self.modelName))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    func validate() async -> Bool {
        !apiKey.isEmpty && apiKey.hasPrefix("sk-")
    }
}
