// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import Foundation

/// Central configuration for EvenClaw.
/// Reads from UserDefaults with hardcoded fallbacks.
struct EvenClawConfig {

    private static let defaults = UserDefaults.standard

    // MARK: - OpenAI

    static var openAIKey: String {
        get { defaults.string(forKey: "openAIKey") ?? "" }
        set { defaults.set(newValue, forKey: "openAIKey") }
    }

    // MARK: - OpenClaw Gateway

    static var openClawHost: String {
        get { defaults.string(forKey: "openClawHost") ?? "http://Aishas-Mac-mini.local" }
        set { defaults.set(newValue, forKey: "openClawHost") }
    }

    static var openClawPort: Int {
        get {
            let v = defaults.integer(forKey: "openClawPort")
            return v != 0 ? v : 18789
        }
        set { defaults.set(newValue, forKey: "openClawPort") }
    }

    static var openClawToken: String {
        get { defaults.string(forKey: "openClawToken") ?? "512cd5178a03ca296e4be099f76e86fadbea0e3889445534" }
        set { defaults.set(newValue, forKey: "openClawToken") }
    }

    static var isOpenClawConfigured: Bool {
        !openClawToken.isEmpty && !openClawHost.isEmpty
    }

    // MARK: - TTS

    static var ttsEnabled: Bool {
        get { defaults.object(forKey: "ttsEnabled") != nil ? defaults.bool(forKey: "ttsEnabled") : true }
        set { defaults.set(newValue, forKey: "ttsEnabled") }
    }

    static var ttsVoice: String {
        get { defaults.string(forKey: "ttsVoice") ?? "nova" }
        set { defaults.set(newValue, forKey: "ttsVoice") }
    }

    // MARK: - VAD

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

    // MARK: - Wake Word

    static var wakeWordEnabled: Bool {
        get { defaults.object(forKey: "wakeWordEnabled") != nil ? defaults.bool(forKey: "wakeWordEnabled") : true }
        set { defaults.set(newValue, forKey: "wakeWordEnabled") }
    }

    static var wakeWordPhrase: String {
        get { defaults.string(forKey: "wakeWordPhrase") ?? "hey aisha" }
        set { defaults.set(newValue, forKey: "wakeWordPhrase") }
    }

    // MARK: - Live Dictation

    static var liveDictationEnabled: Bool {
        get { defaults.object(forKey: "liveDictationEnabled") != nil ? defaults.bool(forKey: "liveDictationEnabled") : true }
        set { defaults.set(newValue, forKey: "liveDictationEnabled") }
    }

    static var hudUpdateRate: TimeInterval {
        get {
            let v = defaults.double(forKey: "hudUpdateRate")
            return v > 0 ? v : 0.5 // 500ms
        }
        set { defaults.set(newValue, forKey: "hudUpdateRate") }
    }

    // MARK: - Gesture

    static var confirmationTimeout: TimeInterval {
        get {
            let v = defaults.double(forKey: "confirmationTimeout")
            return v > 0 ? v : 5.0 // 5 seconds
        }
        set { defaults.set(newValue, forKey: "confirmationTimeout") }
    }

    static var responseDisplayDuration: TimeInterval {
        get {
            let v = defaults.double(forKey: "responseDisplayDuration")
            return v > 0 ? v : 15.0 // 15 seconds
        }
        set { defaults.set(newValue, forKey: "responseDisplayDuration") }
    }
}
