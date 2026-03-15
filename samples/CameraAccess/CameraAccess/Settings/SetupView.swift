// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// SetupView.swift
// Multi-provider AI backend setup screen.

import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void

    @State private var selectedProvider: AIProviderType = KeychainManager.activeProvider ?? .openClaw

    // OpenClaw
    @State private var openClawHost = EvenClawConfig.openClawHost
    @State private var openClawPort = String(EvenClawConfig.openClawPort)
    @State private var openClawToken = EvenClawConfig.openClawToken

    // Anthropic
    @State private var anthropicKey = EvenClawConfig.anthropicAPIKey
    @State private var anthropicModel = EvenClawConfig.anthropicModel

    // OpenAI
    @State private var openAIKey = EvenClawConfig.openAIKey
    @State private var openAIModel = EvenClawConfig.openAIModel

    // Gemini
    @State private var geminiKey = EvenClawConfig.geminiAPIKey
    @State private var geminiModel = EvenClawConfig.geminiModel

    // Custom
    @State private var customBaseURL = EvenClawConfig.customBaseURL
    @State private var customKey = EvenClawConfig.customAPIKey
    @State private var customModel = EvenClawConfig.customModel

    // Validation
    @State private var isValidating = false
    @State private var validationResult: String?
    @State private var validationSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                }

                switch selectedProvider {
                case .openClaw:
                    openClawSection
                case .anthropic:
                    anthropicSection
                case .openAI:
                    openAISection
                case .gemini:
                    geminiSection
                case .custom:
                    customSection
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Validating...")
                            } else {
                                Image(systemName: "checkmark.shield")
                                Text("Validate & Save")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isValidating || !hasRequiredFields)
                    .buttonStyle(.borderedProminent)

                    if let result = validationResult {
                        Label(result, systemImage: validationSuccess ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(validationSuccess ? .green : .red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Setup AI Backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if EvenClawConfig.isProviderConfigured {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Provider Sections

    private var openClawSection: some View {
        Section("OpenClaw Gateway") {
            TextField("Host URL (e.g. http://192.168.1.100)", text: $openClawHost)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .textContentType(.URL)
            TextField("Port", text: $openClawPort)
                .keyboardType(.numberPad)
            SecureField("Session Token", text: $openClawToken)
        }
    }

    private var anthropicSection: some View {
        Section("Anthropic") {
            SecureField("API Key (sk-ant-...)", text: $anthropicKey)
                .autocapitalization(.none)
            Picker("Model", selection: $anthropicModel) {
                ForEach(AnthropicProvider.models, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var openAISection: some View {
        Section("OpenAI") {
            SecureField("API Key (sk-...)", text: $openAIKey)
                .autocapitalization(.none)
            Picker("Model", selection: $openAIModel) {
                ForEach(OpenAIProvider.models, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var geminiSection: some View {
        Section("Google Gemini") {
            SecureField("API Key", text: $geminiKey)
                .autocapitalization(.none)
            Picker("Model", selection: $geminiModel) {
                ForEach(GeminiProvider.models, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var customSection: some View {
        Section("Custom Endpoint (OpenAI-compatible)") {
            TextField("Base URL", text: $customBaseURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
            SecureField("API Key", text: $customKey)
                .autocapitalization(.none)
            TextField("Model Name", text: $customModel)
                .autocapitalization(.none)
        }
    }

    // MARK: - Validation

    private var hasRequiredFields: Bool {
        switch selectedProvider {
        case .openClaw:
            return !openClawHost.isEmpty && !openClawToken.isEmpty
        case .anthropic:
            return !anthropicKey.isEmpty
        case .openAI:
            return !openAIKey.isEmpty
        case .gemini:
            return !geminiKey.isEmpty
        case .custom:
            return !customBaseURL.isEmpty && !customKey.isEmpty && !customModel.isEmpty
        }
    }

    private func validateAndSave() async {
        isValidating = true
        validationResult = nil

        // Save first so the provider factory can read from Keychain
        saveCredentials()

        guard let provider = AIProviderFactory.create(for: selectedProvider) else {
            validationResult = "Failed to create provider"
            validationSuccess = false
            isValidating = false
            return
        }

        let result = await provider.validate()
        isValidating = false

        if result.valid {
            EvenClawConfig.activeProvider = selectedProvider
            validationResult = "\(selectedProvider.displayName) connected successfully"
            validationSuccess = true

            // Dismiss after brief delay to show success
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
            onComplete()
        } else {
            validationResult = result.error ?? "Validation failed"
            validationSuccess = false
        }
    }

    private func saveCredentials() {
        switch selectedProvider {
        case .openClaw:
            EvenClawConfig.openClawHost = openClawHost
            EvenClawConfig.openClawPort = Int(openClawPort) ?? 18789
            EvenClawConfig.openClawToken = openClawToken
        case .anthropic:
            EvenClawConfig.anthropicAPIKey = anthropicKey
            EvenClawConfig.anthropicModel = anthropicModel
        case .openAI:
            EvenClawConfig.openAIKey = openAIKey
            EvenClawConfig.openAIModel = openAIModel
        case .gemini:
            EvenClawConfig.geminiAPIKey = geminiKey
            EvenClawConfig.geminiModel = geminiModel
        case .custom:
            EvenClawConfig.customBaseURL = customBaseURL
            EvenClawConfig.customAPIKey = customKey
            EvenClawConfig.customModel = customModel
        }
    }
}
