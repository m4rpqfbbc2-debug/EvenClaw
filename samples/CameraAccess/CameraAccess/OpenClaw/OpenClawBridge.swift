// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OpenClawBridge.swift
// HTTP client for the OpenClaw gateway.

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

    private let session: URLSession
    private let pingSession: URLSession
    private var sessionKey: String
    private var conversationHistory: [[String: String]] = []
    private let maxHistoryTurns = 10

    /// The session key that merges EvenClaw voice into the main WhatsApp conversation.
    /// This must match the owner's WhatsApp DM session so all platforms share one thread.
    static let mergedSessionKey = "agent:main:whatsapp:dm:+447964018875"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)

        let pingConfig = URLSessionConfiguration.default
        pingConfig.timeoutIntervalForRequest = 5
        self.pingSession = URLSession(configuration: pingConfig)

        self.sessionKey = OpenClawBridge.mergedSessionKey
    }

    var baseURL: String {
        "\(EvenClawConfig.openClawHost):\(EvenClawConfig.openClawPort)"
    }

    func checkConnection() async {
        guard EvenClawConfig.isOpenClawConfigured else {
            connectionState = .notConfigured; return
        }
        connectionState = .checking
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            connectionState = .unreachable("Invalid URL"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(EvenClawConfig.openClawToken)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await pingSession.data(for: request)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                connectionState = .connected
                NSLog("[OpenClaw] Gateway reachable (HTTP %d)", http.statusCode)
            } else {
                connectionState = .unreachable("Unexpected response")
            }
        } catch {
            connectionState = .unreachable(error.localizedDescription)
            NSLog("[OpenClaw] Gateway unreachable: %@", error.localizedDescription)
        }
    }

    func resetSession() {
        // Keep the merged session key — just clear local history cache
        conversationHistory = []
    }

    /// Send a message to OpenClaw and get a response.
    func sendMessage(_ text: String) async -> (success: Bool, response: String) {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return (false, "Invalid gateway URL")
        }

        conversationHistory.append(["role": "user", "content": text])
        if conversationHistory.count > maxHistoryTurns * 2 {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(EvenClawConfig.openClawToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")

        let body: [String: Any] = [
            "model": "openclaw",
            "messages": conversationHistory,
            "stream": false
        ]

        NSLog("[OpenClaw] Sending: %@", String(text.prefix(100)))

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse

            guard let code = http?.statusCode, (200...299).contains(code) else {
                let code = http?.statusCode ?? 0
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[OpenClaw] Error HTTP %d: %@", code, String(bodyStr.prefix(200)))
                return (false, "HTTP \(code)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                conversationHistory.append(["role": "assistant", "content": content])
                NSLog("[OpenClaw] Response: %@", String(content.prefix(200)))
                return (true, content)
            }

            let raw = String(data: data, encoding: .utf8) ?? "OK"
            conversationHistory.append(["role": "assistant", "content": raw])
            return (true, raw)
        } catch {
            NSLog("[OpenClaw] Error: %@", error.localizedDescription)
            return (false, error.localizedDescription)
        }
    }
}
