// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OpenClawProvider.swift
// OpenClaw gateway integration — local or remote server with /api/chat endpoint.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "OpenClaw")

final class OpenClawProvider: AIProvider, @unchecked Sendable {

    let name = "OpenClaw"
    let modelName: String

    private let host: String
    private let token: String

    init(host: String, token: String) {
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.modelName = "OpenClaw"
    }

    convenience init?() {
        guard let host = KeychainManager.load(.openClawHost),
              !host.isEmpty else { return nil }
        let token = KeychainManager.load(.openClawToken) ?? ""
        self.init(host: host, token: token)
    }

    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String {
        let url = URL(string: "\(host)/api/chat")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 2 minutes for tool calls

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "message": prompt,
            "history": history.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Sending to OpenClaw: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIProviderError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return responseText.isEmpty ? "No response received." : responseText
    }

    func validate() async -> Bool {
        guard let url = URL(string: "\(host)/api/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                return true
            }
        } catch {}
        return false
    }
}
