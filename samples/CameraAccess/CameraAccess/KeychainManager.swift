// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// KeychainManager.swift
// Secure credential storage using iOS Keychain.

import Foundation
import Security

struct KeychainManager {

    private static let service = "ai.xgx.evenclaw"

    enum Key: String {
        case openClawHost = "openclaw_host"
        case openClawPort = "openclaw_port"
        case openClawToken = "openclaw_token"
        case anthropicAPIKey = "anthropic_api_key"
        case anthropicModel = "anthropic_model"
        case openAIAPIKey = "openai_api_key"
        case openAIModel = "openai_model"
        case geminiAPIKey = "gemini_api_key"
        case geminiModel = "gemini_model"
        case customBaseURL = "custom_base_url"
        case customAPIKey = "custom_api_key"
        case customModel = "custom_model"
        case activeProvider = "active_provider"
    }

    // MARK: - CRUD

    static func save(_ value: String, forKey key: Key) {
        guard !value.isEmpty else { delete(key); return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience

    static var activeProvider: AIProviderType? {
        get {
            guard let raw = load(.activeProvider) else { return nil }
            return AIProviderType(rawValue: raw)
        }
        set {
            if let v = newValue {
                save(v.rawValue, forKey: .activeProvider)
            } else {
                delete(.activeProvider)
            }
        }
    }

    static var isProviderConfigured: Bool {
        guard let provider = activeProvider else { return false }
        switch provider {
        case .openClaw:
            return load(.openClawToken) != nil && load(.openClawHost) != nil
        case .anthropic:
            return load(.anthropicAPIKey) != nil
        case .openAI:
            return load(.openAIAPIKey) != nil
        case .gemini:
            return load(.geminiAPIKey) != nil
        case .custom:
            return load(.customBaseURL) != nil && load(.customAPIKey) != nil
        }
    }

    /// Migrate existing UserDefaults credentials to Keychain (one-time).
    static func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard

        if let host = defaults.string(forKey: "openClawHost"), !host.isEmpty,
           load(.openClawHost) == nil {
            save(host, forKey: .openClawHost)
        }
        if let token = defaults.string(forKey: "openClawToken"), !token.isEmpty,
           load(.openClawToken) == nil {
            save(token, forKey: .openClawToken)
        }
        if let key = defaults.string(forKey: "openAIKey"), !key.isEmpty,
           load(.openAIAPIKey) == nil {
            save(key, forKey: .openAIAPIKey)
        }

        let port = defaults.integer(forKey: "openClawPort")
        if port != 0, load(.openClawPort) == nil {
            save(String(port), forKey: .openClawPort)
        }

        // If we migrated OpenClaw credentials and no provider is set, default to OpenClaw
        if activeProvider == nil && load(.openClawToken) != nil {
            activeProvider = .openClaw
        }

        // Clean up UserDefaults secrets after migration
        defaults.removeObject(forKey: "openClawToken")
        defaults.removeObject(forKey: "openAIKey")
    }
}
