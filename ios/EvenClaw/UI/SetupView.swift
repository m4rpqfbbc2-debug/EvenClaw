// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// SetupView.swift
// Multi-provider BYOK configuration. All keys stored in iOS Keychain.

import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    var onComplete: ((any AIProvider)?) -> Void

    @State private var selectedProvider: AIProviderType = .openClaw
    @State private var isValidating = false
    @State private var validationMessage = ""

    // OpenClaw
    @State private var openClawHost = ""
    @State private var openClawToken = ""

    // Anthropic
    @State private var anthropicKey = ""
    @State private var anthropicModel = AnthropicProvider.availableModels[0]

    // OpenAI
    @State private var openAIKey = ""
    @State private var openAIModel = OpenAIProvider.availableModels[0]

    // Gemini
    @State private var geminiKey = ""
    @State private var geminiModel = GeminiProvider.availableModels[0]

    // Custom
    @State private var customBaseURL = ""
    @State private var customAPIKey = ""
    @State private var customModel = ""

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title
                    Text("AI PROVIDER SETUP")
                        .font(MatrixTheme.fontHeading)
                        .foregroundStyle(MatrixTheme.primary)
                        .padding(.top)

                    // Provider picker
                    providerPicker

                    // Provider-specific fields
                    providerFields

                    // Validation message
                    if !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(MatrixTheme.fontCaption)
                            .foregroundStyle(validationMessage.contains("Error") ? MatrixTheme.error : MatrixTheme.success)
                    }

                    // Save button
                    HStack {
                        Button {
                            saveAndValidate()
                        } label: {
                            HStack {
                                if isValidating {
                                    ProgressView()
                                        .tint(MatrixTheme.background)
                                        .scaleEffect(0.7)
                                }
                                Text("SAVE & CONNECT")
                            }
                            .matrixButton()
                        }
                        .disabled(isValidating)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Text("CANCEL")
                                .matrixOutlineButton()
                        }
                    }
                }
                .padding()
            }

            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear { loadSaved() }
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROVIDER")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)

            HStack(spacing: 0) {
                ForEach(AIProviderType.allCases) { type in
                    Button {
                        selectedProvider = type
                    } label: {
                        Text(type.rawValue)
                            .font(MatrixTheme.mono(11, weight: .semibold))
                            .foregroundStyle(
                                selectedProvider == type ? MatrixTheme.background : MatrixTheme.primary
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                selectedProvider == type ? MatrixTheme.primary : Color.clear
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(MatrixTheme.border, lineWidth: 1)
                            )
                    }
                }
            }

            Text(selectedProvider.description)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
        }
    }

    // MARK: - Provider Fields

    @ViewBuilder
    private var providerFields: some View {
        switch selectedProvider {
        case .openClaw:
            fieldGroup {
                matrixField("HOST URL", text: $openClawHost, placeholder: "http://192.168.1.162:3001")
                matrixField("TOKEN (optional)", text: $openClawToken, placeholder: "session token", isSecure: true)
            }

        case .anthropic:
            fieldGroup {
                matrixField("API KEY", text: $anthropicKey, placeholder: "sk-ant-...", isSecure: true)
                modelPicker("MODEL", selection: $anthropicModel, options: AnthropicProvider.availableModels)
            }

        case .openAI:
            fieldGroup {
                matrixField("API KEY", text: $openAIKey, placeholder: "sk-...", isSecure: true)
                modelPicker("MODEL", selection: $openAIModel, options: OpenAIProvider.availableModels)
            }

        case .gemini:
            fieldGroup {
                matrixField("API KEY", text: $geminiKey, placeholder: "AI...", isSecure: true)
                modelPicker("MODEL", selection: $geminiModel, options: GeminiProvider.availableModels)
            }

        case .custom:
            fieldGroup {
                matrixField("BASE URL", text: $customBaseURL, placeholder: "http://localhost:11434")
                matrixField("API KEY (optional)", text: $customAPIKey, placeholder: "api key", isSecure: true)
                matrixField("MODEL NAME", text: $customModel, placeholder: "llama3.1")
            }
        }
    }

    // MARK: - Helpers

    private func fieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
    }

    private func matrixField(_ label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)

            if isSecure {
                SecureField(placeholder, text: text)
                    .matrixTextField()
            } else {
                TextField(placeholder, text: text)
                    .matrixTextField()
            }
        }
    }

    private func modelPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { model in
                    Button {
                        selection.wrappedValue = model
                    } label: {
                        Text(model.components(separatedBy: "-").prefix(3).joined(separator: "-"))
                            .font(MatrixTheme.mono(10))
                            .foregroundStyle(
                                selection.wrappedValue == model ? MatrixTheme.background : MatrixTheme.primary
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                selection.wrappedValue == model ? MatrixTheme.primary : Color.clear
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(MatrixTheme.border, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Save / Validate

    private func loadSaved() {
        if let saved = KeychainManager.load(.selectedProvider),
           let type = AIProviderType(rawValue: saved) {
            selectedProvider = type
        }
        openClawHost = KeychainManager.load(.openClawHost) ?? ""
        openClawToken = KeychainManager.load(.openClawToken) ?? ""
        anthropicKey = KeychainManager.load(.anthropicAPIKey) ?? ""
        anthropicModel = KeychainManager.load(.anthropicModel) ?? AnthropicProvider.availableModels[0]
        openAIKey = KeychainManager.load(.openAIAPIKey) ?? ""
        openAIModel = KeychainManager.load(.openAIModel) ?? OpenAIProvider.availableModels[0]
        geminiKey = KeychainManager.load(.geminiAPIKey) ?? ""
        geminiModel = KeychainManager.load(.geminiModel) ?? GeminiProvider.availableModels[0]
        customBaseURL = KeychainManager.load(.customBaseURL) ?? ""
        customAPIKey = KeychainManager.load(.customAPIKey) ?? ""
        customModel = KeychainManager.load(.customModel) ?? ""
    }

    private func saveAndValidate() {
        isValidating = true
        validationMessage = ""

        // Save to keychain
        KeychainManager.save(selectedProvider.rawValue, for: .selectedProvider)

        switch selectedProvider {
        case .openClaw:
            KeychainManager.save(openClawHost, for: .openClawHost)
            KeychainManager.save(openClawToken, for: .openClawToken)
        case .anthropic:
            KeychainManager.save(anthropicKey, for: .anthropicAPIKey)
            KeychainManager.save(anthropicModel, for: .anthropicModel)
        case .openAI:
            KeychainManager.save(openAIKey, for: .openAIAPIKey)
            KeychainManager.save(openAIModel, for: .openAIModel)
        case .gemini:
            KeychainManager.save(geminiKey, for: .geminiAPIKey)
            KeychainManager.save(geminiModel, for: .geminiModel)
        case .custom:
            KeychainManager.save(customBaseURL, for: .customBaseURL)
            KeychainManager.save(customAPIKey, for: .customAPIKey)
            KeychainManager.save(customModel, for: .customModel)
        }

        // Create provider and validate
        Task {
            let provider = createProvider()
            if let provider {
                let valid = await provider.validate()
                await MainActor.run {
                    isValidating = false
                    if valid {
                        validationMessage = "Connected to \(selectedProvider.displayName)"
                        onComplete(provider)
                        dismiss()
                    } else {
                        validationMessage = "Error: Could not validate credentials"
                    }
                }
            } else {
                await MainActor.run {
                    isValidating = false
                    validationMessage = "Error: Missing required fields"
                }
            }
        }
    }

    private func createProvider() -> (any AIProvider)? {
        switch selectedProvider {
        case .openClaw:
            guard !openClawHost.isEmpty else { return nil }
            return OpenClawProvider(host: openClawHost, token: openClawToken)
        case .anthropic:
            guard !anthropicKey.isEmpty else { return nil }
            return AnthropicProvider(apiKey: anthropicKey, model: anthropicModel)
        case .openAI:
            guard !openAIKey.isEmpty else { return nil }
            return OpenAIProvider(apiKey: openAIKey, model: openAIModel)
        case .gemini:
            guard !geminiKey.isEmpty else { return nil }
            return GeminiProvider(apiKey: geminiKey, model: geminiModel)
        case .custom:
            guard !customBaseURL.isEmpty else { return nil }
            return CustomProvider(baseURL: customBaseURL, apiKey: customAPIKey, model: customModel)
        }
    }
}
