// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // AI Backend
    @State private var showProviderSetup = false

    // Voice
    @State private var ttsEnabled = EvenClawConfig.ttsEnabled
    @State private var ttsVoice = EvenClawConfig.ttsVoice
    @State private var silenceThreshold = Double(EvenClawConfig.silenceThreshold)
    @State private var silenceDuration = EvenClawConfig.silenceDuration

    // Glasses
    @State private var conversateEnabled = EvenClawConfig.conversateEnabled
    @State private var liveDictationEnabled = EvenClawConfig.liveDictationEnabled
    @State private var wakeWordEnabled = EvenClawConfig.wakeWordEnabled

    // Advanced
    @State private var confirmationTimeout = EvenClawConfig.confirmationTimeout

    private let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

    var body: some View {
        NavigationStack {
            ZStack {
                MatrixColor.terminal.ignoresSafeArea()

                Form {
                    // MARK: - AI Backend
                    Section {
                        HStack {
                            Text("PROVIDER")
                                .font(MatrixFont.caption)
                                .foregroundStyle(MatrixColor.dimPhosphor)
                            Spacer()
                            Text(EvenClawConfig.activeProvider?.displayName.uppercased() ?? "NOT CONFIGURED")
                                .font(MatrixFont.caption)
                                .foregroundStyle(MatrixColor.phosphor)
                        }

                        if let provider = EvenClawConfig.activeProvider {
                            HStack {
                                Text(providerDetailLabel(provider))
                                    .font(MatrixFont.caption)
                                    .foregroundStyle(MatrixColor.dimPhosphor)
                                Spacer()
                                Text(providerDetailValue(provider))
                                    .font(MatrixFont.caption)
                                    .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }

                        Button {
                            showProviderSetup = true
                        } label: {
                            Text("[ CHANGE PROVIDER ]")
                                .font(MatrixFont.caption)
                                .foregroundStyle(MatrixColor.amber)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } header: {
                        sectionHeader("AI BACKEND")
                    }

                    // MARK: - Voice
                    Section {
                        matrixToggle("ENABLE TTS", isOn: $ttsEnabled)
                        Picker("VOICE", selection: $ttsVoice) {
                            ForEach(voices, id: \.self) { v in
                                Text(v.uppercased())
                                    .font(MatrixFont.caption)
                                    .tag(v)
                            }
                        }
                        .font(MatrixFont.caption)
                        .foregroundStyle(MatrixColor.phosphor)

                        VStack(alignment: .leading) {
                            Text("SILENCE SENSITIVITY: \(silenceThreshold, specifier: "%.3f")")
                                .font(MatrixFont.micro)
                                .foregroundStyle(MatrixColor.dimPhosphor)
                            Slider(value: $silenceThreshold, in: 0.001...0.05, step: 0.001)
                                .tint(MatrixColor.phosphor)
                        }
                        VStack(alignment: .leading) {
                            Text("PAUSE TIMEOUT: \(silenceDuration, specifier: "%.1f")s")
                                .font(MatrixFont.micro)
                                .foregroundStyle(MatrixColor.dimPhosphor)
                            Text("How long to wait after you stop speaking before sending")
                                .font(MatrixFont.micro)
                                .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.4))
                            Slider(value: $silenceDuration, in: 1.0...8.0, step: 0.5)
                                .tint(MatrixColor.phosphor)
                        }
                    } header: {
                        sectionHeader("VOICE")
                    }

                    // MARK: - Glasses
                    Section {
                        matrixToggle("ENABLE G2 CONVERSATE", isOn: $conversateEnabled)
                        Text("Long-press left TouchBar on G2 to activate")
                            .font(MatrixFont.micro)
                            .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.5))
                        matrixToggle("ENABLE LIVE DICTATION", isOn: $liveDictationEnabled)
                    } header: {
                        sectionHeader("GLASSES")
                    }

                    // MARK: - Input Mode
                    Section {
                        Text("Primary: Arm gestures (slide/tap/double-tap)")
                            .font(MatrixFont.micro)
                            .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.5))
                        matrixToggle("WAKE WORD ('HEY AISHA')", isOn: $wakeWordEnabled)
                        Text("Optional. Uses continuous mic — higher battery drain.")
                            .font(MatrixFont.micro)
                            .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.4))
                    } header: {
                        sectionHeader("INPUT MODE")
                    }

                    // MARK: - Advanced
                    Section {
                        VStack(alignment: .leading) {
                            Text("CONFIRMATION TIMEOUT: \(confirmationTimeout, specifier: "%.1f")s")
                                .font(MatrixFont.micro)
                                .foregroundStyle(MatrixColor.dimPhosphor)
                            Slider(value: $confirmationTimeout, in: 2.0...10.0, step: 0.5)
                                .tint(MatrixColor.phosphor)
                        }
                    } header: {
                        sectionHeader("ADVANCED")
                    }

                    // MARK: - About
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EVENCLAW v5.1")
                                .font(MatrixFont.caption)
                                .foregroundStyle(MatrixColor.phosphor)
                            Text("XGX.ai")
                                .font(MatrixFont.micro)
                                .foregroundStyle(MatrixColor.amber)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("SAVE")
                            .font(MatrixFont.caption)
                            .foregroundStyle(MatrixColor.phosphor)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("CANCEL")
                            .font(MatrixFont.caption)
                            .foregroundStyle(MatrixColor.dimPhosphor)
                    }
                }
            }
            .sheet(isPresented: $showProviderSetup) {
                SetupView(onComplete: {})
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MatrixFont.micro)
            .foregroundStyle(MatrixColor.amber)
            .tracking(2)
    }

    private func matrixToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(MatrixFont.caption)
                .foregroundStyle(MatrixColor.phosphor)
        }
        .tint(MatrixColor.phosphor)
    }

    private func providerDetailLabel(_ provider: AIProviderType) -> String {
        switch provider {
        case .openClaw: return "GATEWAY"
        case .custom: return "ENDPOINT"
        default: return "MODEL"
        }
    }

    private func providerDetailValue(_ provider: AIProviderType) -> String {
        switch provider {
        case .openClaw: return EvenClawConfig.openClawHost
        case .anthropic: return EvenClawConfig.anthropicModel
        case .openAI: return EvenClawConfig.openAIModel
        case .gemini: return EvenClawConfig.geminiModel
        case .custom: return EvenClawConfig.customBaseURL
        }
    }

    private func save() {
        EvenClawConfig.ttsEnabled = ttsEnabled
        EvenClawConfig.ttsVoice = ttsVoice
        EvenClawConfig.silenceThreshold = Float(silenceThreshold)
        EvenClawConfig.silenceDuration = silenceDuration
        EvenClawConfig.conversateEnabled = conversateEnabled
        EvenClawConfig.liveDictationEnabled = liveDictationEnabled
        EvenClawConfig.confirmationTimeout = confirmationTimeout
        EvenClawConfig.wakeWordEnabled = wakeWordEnabled
    }
}
