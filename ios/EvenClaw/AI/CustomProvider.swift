// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// CustomProvider.swift
// Any OpenAI-compatible endpoint (e.g. Ollama, LM Studio, vLLM, etc).

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Custom")

final class CustomProvider: AIProvider, @unchecked Sendable {

    let name = "Custom"
    let modelName: String

    private let baseURL: String
    private let apiKey: String

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.modelName = model
    }

    convenience init?() {
        guard let baseURL = KeychainManager.load(.customBaseURL),
              !baseURL.isEmpty else { return nil }
        let key = KeychainManager.load(.customAPIKey) ?? ""
        let model = KeychainManager.load(.customModel) ?? "default"
        self.init(baseURL: baseURL, apiKey: key, model: model)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        let endpoint = "\(baseURL)/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw AIProviderError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

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

        log.info("Sending to Custom (\(self.baseURL), model: \(self.modelName))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        // OpenAI-compatible response format
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
        !baseURL.isEmpty
    }
}
