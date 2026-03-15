// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AIProvider.swift
// Protocol + implementations for multi-provider AI backend.

import Foundation

// MARK: - Provider Type

enum AIProviderType: String, CaseIterable, Identifiable {
    case openClaw = "openclaw"
    case anthropic = "anthropic"
    case openAI = "openai"
    case gemini = "gemini"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openClaw: return "OpenClaw"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .custom: return "Custom Endpoint"
        }
    }
}

// MARK: - Protocol

protocol AIProvider {
    var providerType: AIProviderType { get }
    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String)
    func validate() async -> (valid: Bool, error: String?)
}

// MARK: - OpenClaw Provider

struct OpenClawProvider: AIProvider {
    let providerType: AIProviderType = .openClaw
    let host: String
    let port: Int
    let token: String

    private var baseURL: String { "\(host):\(port)" }

    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String) {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return (false, "Invalid gateway URL")
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are responding via smart glasses HUD. Be concise but complete. No markdown formatting."]
        ]
        messages.append(contentsOf: history)
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": "openclaw",
            "messages": messages,
            "stream": false
        ]

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 120
            return c
        }())

        for attempt in 1...2 {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("agent:main:evenclaw", forHTTPHeaderField: "x-openclaw-session-key")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse

                guard let code = http?.statusCode, (200...299).contains(code) else {
                    let code = http?.statusCode ?? 0
                    if attempt == 1 && (code == 0 || code >= 500) {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    return (false, "HTTP \(code)")
                }

                if let content = extractOpenAIContent(from: data) {
                    return (true, content)
                }
                return (true, String(data: data, encoding: .utf8) ?? "OK")
            } catch {
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                return (false, error.localizedDescription)
            }
        }
        return (false, "Unexpected error")
    }

    func validate() async -> (valid: Bool, error: String?) {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            return (false, "Invalid URL")
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                return (true, nil)
            }
            return (false, "Unexpected response")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Anthropic Provider

struct AnthropicProvider: AIProvider {
    let providerType: AIProviderType = .anthropic
    let apiKey: String
    let model: String

    static let models = [
        "claude-sonnet-4-6", "claude-opus-4-6",
        "claude-haiku-4-5-20251001", "claude-sonnet-4-5-20250514"
    ]
    static let defaultModel = "claude-sonnet-4-6"

    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return (false, "Invalid URL")
        }

        var anthropicMessages: [[String: String]] = []
        for msg in history {
            if let role = msg["role"], let content = msg["content"], role != "system" {
                anthropicMessages.append(["role": role, "content": content])
            }
        }
        anthropicMessages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": "You are responding via smart glasses HUD. Be concise but complete. No markdown formatting.",
            "messages": anthropicMessages
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            guard let code = http?.statusCode, (200...299).contains(code) else {
                let code = http?.statusCode ?? 0
                let errBody = String(data: data, encoding: .utf8) ?? ""
                return (false, "HTTP \(code): \(String(errBody.prefix(200)))")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                return (true, text)
            }
            return (false, "Could not parse response")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func validate() async -> (valid: Bool, error: String?) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return (false, "Invalid URL")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "messages": [["role": "user", "content": "hi"]]
        ]
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return (true, nil)
            } else if let http = response as? HTTPURLResponse {
                return (false, "HTTP \(http.statusCode)")
            }
            return (false, "Unknown error")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - OpenAI Provider

struct OpenAIProvider: AIProvider {
    let providerType: AIProviderType = .openAI
    let apiKey: String
    let model: String

    static let models = ["gpt-4o", "gpt-4-turbo", "gpt-4o-mini", "gpt-4"]
    static let defaultModel = "gpt-4o"

    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return (false, "Invalid URL")
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are responding via smart glasses HUD. Be concise but complete. No markdown formatting."]
        ]
        messages.append(contentsOf: history)
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            guard let code = http?.statusCode, (200...299).contains(code) else {
                let code = http?.statusCode ?? 0
                return (false, "HTTP \(code)")
            }

            if let content = extractOpenAIContent(from: data) {
                return (true, content)
            }
            return (false, "Could not parse response")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func validate() async -> (valid: Bool, error: String?) {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return (false, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return (true, nil)
            }
            return (false, "Invalid API key")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Gemini Provider

struct GeminiProvider: AIProvider {
    let providerType: AIProviderType = .gemini
    let apiKey: String
    let model: String

    static let models = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
    static let defaultModel = "gemini-2.5-flash"

    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            return (false, "Invalid URL")
        }

        var contents: [[String: Any]] = []
        for msg in history {
            if let role = msg["role"], let content = msg["content"], role != "system" {
                let geminiRole = role == "assistant" ? "model" : "user"
                contents.append(["role": geminiRole, "parts": [["text": content]]])
            }
        }
        contents.append(["role": "user", "parts": [["text": prompt]]])

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": "You are responding via smart glasses HUD. Be concise but complete. No markdown formatting."]]],
            "generationConfig": ["maxOutputTokens": 1024]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            guard let code = http?.statusCode, (200...299).contains(code) else {
                let code = http?.statusCode ?? 0
                return (false, "HTTP \(code)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return (true, text)
            }
            return (false, "Could not parse response")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func validate() async -> (valid: Bool, error: String?) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            return (false, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return (true, nil)
            }
            return (false, "Invalid API key")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Custom Provider (OpenAI-compatible)

struct CustomProvider: AIProvider {
    let providerType: AIProviderType = .custom
    let baseURL: String
    let apiKey: String
    let model: String

    func sendMessage(_ prompt: String, history: [[String: String]]) async -> (success: Bool, response: String) {
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)v1/chat/completions" : "\(baseURL)/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            return (false, "Invalid URL")
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are responding via smart glasses HUD. Be concise but complete. No markdown formatting."]
        ]
        messages.append(contentsOf: history)
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            guard let code = http?.statusCode, (200...299).contains(code) else {
                let code = http?.statusCode ?? 0
                return (false, "HTTP \(code)")
            }

            if let content = extractOpenAIContent(from: data) {
                return (true, content)
            }
            return (true, String(data: data, encoding: .utf8) ?? "OK")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func validate() async -> (valid: Bool, error: String?) {
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)v1/models" : "\(baseURL)/v1/models"
        guard let url = URL(string: endpoint) else {
            return (false, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                return (true, nil)
            }
            return (false, "Unreachable")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Factory

enum AIProviderFactory {
    static func create(for type: AIProviderType) -> AIProvider? {
        switch type {
        case .openClaw:
            guard let host = KeychainManager.load(.openClawHost),
                  let token = KeychainManager.load(.openClawToken) else { return nil }
            let port = Int(KeychainManager.load(.openClawPort) ?? "18789") ?? 18789
            return OpenClawProvider(host: host, port: port, token: token)

        case .anthropic:
            guard let key = KeychainManager.load(.anthropicAPIKey) else { return nil }
            let model = KeychainManager.load(.anthropicModel) ?? AnthropicProvider.defaultModel
            return AnthropicProvider(apiKey: key, model: model)

        case .openAI:
            guard let key = KeychainManager.load(.openAIAPIKey) else { return nil }
            let model = KeychainManager.load(.openAIModel) ?? OpenAIProvider.defaultModel
            return OpenAIProvider(apiKey: key, model: model)

        case .gemini:
            guard let key = KeychainManager.load(.geminiAPIKey) else { return nil }
            let model = KeychainManager.load(.geminiModel) ?? GeminiProvider.defaultModel
            return GeminiProvider(apiKey: key, model: model)

        case .custom:
            guard let baseURL = KeychainManager.load(.customBaseURL),
                  let key = KeychainManager.load(.customAPIKey) else { return nil }
            let model = KeychainManager.load(.customModel) ?? "default"
            return CustomProvider(baseURL: baseURL, apiKey: key, model: model)
        }
    }

    static func activeProvider() -> AIProvider? {
        guard let type = KeychainManager.activeProvider else { return nil }
        return create(for: type)
    }
}

// MARK: - Shared Helpers

private func extractOpenAIContent(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any],
          let content = message["content"] as? String else { return nil }
    return content
}
