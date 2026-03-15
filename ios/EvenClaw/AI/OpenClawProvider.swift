// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OpenClawProvider.swift
// OpenClaw gateway integration — connects to /v1/chat/completions endpoint.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "OpenClaw")

final class OpenClawProvider: AIProvider, @unchecked Sendable {

    let name = "OpenClaw"
    let modelName: String

    private let host: String
    private let token: String

    init(host: String, token: String) {
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelName = "OpenClaw"
    }

    convenience init?() {
        guard let host = KeychainManager.load(.openClawHost),
              !host.isEmpty else { return nil }
        let token = KeychainManager.load(.openClawToken) ?? ""
        self.init(host: host, token: token)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        let url = URL(string: "\(host)/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 2 minutes for tool calls

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are Aisha, an AI assistant speaking through Even Realities G2 smart glasses. Keep responses concise (under 400 characters when possible) since they display on a tiny HUD. Be helpful, direct, and conversational."]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "messages": messages,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Sending to OpenClaw: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            log.error("OpenClaw error \(httpResponse.statusCode): \(errorText)")
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return content.isEmpty ? "No response received." : content
    }

    func validate() async -> Bool {
        // Test with a simple chat completion
        guard let url = URL(string: "\(host)/v1/chat/completions") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "messages": [["role": "user", "content": "ping"]],
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            log.error("Validation failed: \(error.localizedDescription)")
        }
        return false
    }
}
