// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import Foundation

/// Central configuration for EvenClaw.
/// Secrets stored in Keychain; non-sensitive prefs in UserDefaults.
struct EvenClawConfig {

    private static let defaults = UserDefaults.standard

    // MARK: - Provider (Keychain-backed)

    static var activeProvider: AIProviderType? {
        get { KeychainManager.activeProvider }
        set { KeychainManager.activeProvider = newValue }
    }

    static var isProviderConfigured: Bool {
        KeychainManager.isProviderConfigured
    }

    // MARK: - OpenClaw Gateway (Keychain-backed)

    static var openClawHost: String {
        get { KeychainManager.load(.openClawHost) ?? "" }
        set { KeychainManager.save(newValue, forKey: .openClawHost) }
    }

    static var openClawPort: Int {
        get { Int(KeychainManager.load(.openClawPort) ?? "18789") ?? 18789 }
        set { KeychainManager.save(String(newValue), forKey: .openClawPort) }
    }

    static var openClawToken: String {
        get { KeychainManager.load(.openClawToken) ?? "" }
        set { KeychainManager.save(newValue, forKey: .openClawToken) }
    }

    static var isOpenClawConfigured: Bool {
        !openClawToken.isEmpty && !openClawHost.isEmpty
    }

    // MARK: - Anthropic (Keychain-backed)

    static var anthropicAPIKey: String {
        get { KeychainManager.load(.anthropicAPIKey) ?? "" }
        set { KeychainManager.save(newValue, forKey: .anthropicAPIKey) }
    }

    static var anthropicModel: String {
        get { KeychainManager.load(.anthropicModel) ?? AnthropicProvider.defaultModel }
        set { KeychainManager.save(newValue, forKey: .anthropicModel) }
    }

    // MARK: - OpenAI (Keychain-backed)

    static var openAIKey: String {
        get { KeychainManager.load(.openAIAPIKey) ?? "" }
        set { KeychainManager.save(newValue, forKey: .openAIAPIKey) }
    }

    static var openAIModel: String {
        get { KeychainManager.load(.openAIModel) ?? OpenAIProvider.defaultModel }
        set { KeychainManager.save(newValue, forKey: .openAIModel) }
    }

    // MARK: - Gemini (Keychain-backed)

    static var geminiAPIKey: String {
        get { KeychainManager.load(.geminiAPIKey) ?? "" }
        set { KeychainManager.save(newValue, forKey: .geminiAPIKey) }
    }

    static var geminiModel: String {
        get { KeychainManager.load(.geminiModel) ?? GeminiProvider.defaultModel }
        set { KeychainManager.save(newValue, forKey: .geminiModel) }
    }

    // MARK: - Custom (Keychain-backed)

    static var customBaseURL: String {
        get { KeychainManager.load(.customBaseURL) ?? "" }
        set { KeychainManager.save(newValue, forKey: .customBaseURL) }
    }

    static var customAPIKey: String {
        get { KeychainManager.load(.customAPIKey) ?? "" }
        set { KeychainManager.save(newValue, forKey: .customAPIKey) }
    }

    static var customModel: String {
        get { KeychainManager.load(.customModel) ?? "" }
        set { KeychainManager.save(newValue, forKey: .customModel) }
    }

    // MARK: - TTS (UserDefaults)

    static var ttsEnabled: Bool {
        get { defaults.object(forKey: "ttsEnabled") != nil ? defaults.bool(forKey: "ttsEnabled") : true }
        set { defaults.set(newValue, forKey: "ttsEnabled") }
    }

    static var ttsVoice: String {
        get { defaults.string(forKey: "ttsVoice") ?? "nova" }
        set { defaults.set(newValue, forKey: "ttsVoice") }
    }

    // MARK: - VAD (UserDefaults)

    static var silenceThreshold: Float {
        get {
            let v = defaults.float(forKey: "silenceThreshold")
            return v > 0 ? v : 0.01
        }
        set { defaults.set(newValue, forKey: "silenceThreshold") }
    }

    static var silenceDuration: TimeInterval {
        get {
            let v = defaults.double(forKey: "silenceDuration")
            return v > 0 ? v : 1.5
        }
        set { defaults.set(newValue, forKey: "silenceDuration") }
    }

    // MARK: - G2 Conversate (UserDefaults)

    static var conversateEnabled: Bool {
        get { defaults.object(forKey: "conversateEnabled") != nil ? defaults.bool(forKey: "conversateEnabled") : true }
        set { defaults.set(newValue, forKey: "conversateEnabled") }
    }

    // MARK: - Live Dictation (UserDefaults)

    static var liveDictationEnabled: Bool {
        get { defaults.object(forKey: "liveDictationEnabled") != nil ? defaults.bool(forKey: "liveDictationEnabled") : true }
        set { defaults.set(newValue, forKey: "liveDictationEnabled") }
    }

    static var hudUpdateRate: TimeInterval {
        get {
            let v = defaults.double(forKey: "hudUpdateRate")
            return v > 0 ? v : 0.5
        }
        set { defaults.set(newValue, forKey: "hudUpdateRate") }
    }

    // MARK: - Gesture (UserDefaults)

    static var confirmationTimeout: TimeInterval {
        get {
            let v = defaults.double(forKey: "confirmationTimeout")
            return v > 0 ? v : 5.0
        }
        set { defaults.set(newValue, forKey: "confirmationTimeout") }
    }

    static var responseDisplayDuration: TimeInterval {
        get {
            let v = defaults.double(forKey: "responseDisplayDuration")
            return v > 0 ? v : 15.0
        }
        set { defaults.set(newValue, forKey: "responseDisplayDuration") }
    }

    // MARK: - Wake Word (UserDefaults) — Phase 2: disabled by default

    static var wakeWordEnabled: Bool {
        get { defaults.object(forKey: "wakeWordEnabled") != nil ? defaults.bool(forKey: "wakeWordEnabled") : false }
        set { defaults.set(newValue, forKey: "wakeWordEnabled") }
    }
}
