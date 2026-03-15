// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AIProvider.swift
// Protocol for all AI backends. Each provider implements this to integrate
// with the state machine.

import Foundation

struct AIMessage: Codable, Equatable {
    let role: String
    let content: String
}

protocol AIProvider: Sendable {
    var name: String { get }
    var modelName: String { get }

    /// Send a message with conversation history and get a response.
    func sendMessage(prompt: String, history: [AIMessage]) async throws -> String

    /// Validate credentials. Returns true if the provider is properly configured.
    func validate() async -> Bool
}

enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case openClaw = "OpenClaw"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case gemini = "Gemini"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .openClaw: return "Local OpenClaw gateway"
        case .anthropic: return "Claude (Anthropic API)"
        case .openAI: return "GPT (OpenAI API)"
        case .gemini: return "Gemini (Google API)"
        case .custom: return "Any OpenAI-compatible endpoint"
        }
    }
}

enum AIProviderError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Provider not configured"
        case .invalidResponse: return "Invalid response from AI"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}
