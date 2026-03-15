// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import Foundation
import Security

enum KeychainManager {

    private static let service = "ai.xgx.evenclaw"

    // MARK: - Keys

    enum Key: String, CaseIterable {
        // Provider selection
        case selectedProvider = "selected_provider"

        // OpenClaw
        case openClawHost = "openclaw_host"
        case openClawToken = "openclaw_token"

        // Anthropic
        case anthropicAPIKey = "anthropic_api_key"
        case anthropicModel = "anthropic_model"

        // OpenAI
        case openAIAPIKey = "openai_api_key"
        case openAIModel = "openai_model"

        // Gemini
        case geminiAPIKey = "gemini_api_key"
        case geminiModel = "gemini_model"

        // Custom
        case customBaseURL = "custom_base_url"
        case customAPIKey = "custom_api_key"
        case customModel = "custom_model"
    }

    // MARK: - CRUD

    static func save(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
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

    static func deleteAll() {
        for key in Key.allCases {
            delete(key)
        }
    }
}
