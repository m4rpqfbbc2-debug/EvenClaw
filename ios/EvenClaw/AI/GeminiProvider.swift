// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// GeminiProvider.swift
// Direct Google Gemini API integration.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Gemini")

final class GeminiProvider: AIProvider, @unchecked Sendable {

    let name = "Gemini"
    let modelName: String

    private let apiKey: String

    static let availableModels = [
        "gemini-2.0-flash",
        "gemini-2.0-pro",
        "gemini-1.5-pro",
        "gemini-1.5-flash",
    ]

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.modelName = model
    }

    convenience init?() {
        guard let key = KeychainManager.load(.geminiAPIKey),
              !key.isEmpty else { return nil }
        let model = KeychainManager.load(.geminiModel) ?? Self.availableModels[0]
        self.init(apiKey: key, model: model)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw AIProviderError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build contents array — Gemini uses "user" and "model" roles
        var contents: [[String: Any]] = []

        // System instruction via first user turn context
        let systemPrompt = "You are Aisha's AI assistant running on Even Realities G2 smart glasses via EvenClaw. Keep responses concise — the display shows ~120 characters at a time. Be direct, helpful, and brief."

        for msg in history.dropLast() {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Sending to Gemini (\(self.modelName))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    func validate() async -> Bool {
        !apiKey.isEmpty
    }
}
