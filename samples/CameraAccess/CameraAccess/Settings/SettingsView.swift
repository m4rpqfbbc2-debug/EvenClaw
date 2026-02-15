// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var openClawHost = EvenClawConfig.openClawHost
    @State private var openClawPort = String(EvenClawConfig.openClawPort)
    @State private var openClawToken = EvenClawConfig.openClawToken
    @State private var openAIKey = EvenClawConfig.openAIKey
    @State private var ttsEnabled = EvenClawConfig.ttsEnabled
    @State private var ttsVoice = EvenClawConfig.ttsVoice
    @State private var silenceThreshold = Double(EvenClawConfig.silenceThreshold)
    @State private var wakeWordEnabled = EvenClawConfig.wakeWordEnabled
    @State private var wakeWordPhrase = EvenClawConfig.wakeWordPhrase
    @State private var liveDictationEnabled = EvenClawConfig.liveDictationEnabled
    @State private var confirmationTimeout = EvenClawConfig.confirmationTimeout

    private let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenClaw Gateway") {
                    TextField("Host", text: $openClawHost)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Port", text: $openClawPort)
                        .keyboardType(.numberPad)
                    SecureField("Token", text: $openClawToken)
                }

                Section("OpenAI") {
                    SecureField("API Key", text: $openAIKey)
                }

                Section("Text-to-Speech") {
                    Toggle("Enable TTS", isOn: $ttsEnabled)
                    Picker("Voice", selection: $ttsVoice) {
                        ForEach(voices, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Wake Word") {
                    Toggle("Enable Wake Word", isOn: $wakeWordEnabled)
                    TextField("Wake Phrase", text: $wakeWordPhrase)
                        .disabled(!wakeWordEnabled)
                        .autocapitalization(.none)
                }

                Section("Live Dictation") {
                    Toggle("Enable Live Dictation", isOn: $liveDictationEnabled)
                    VStack(alignment: .leading) {
                        Text("Confirmation Timeout: \(confirmationTimeout, specifier: "%.1f")s")
                            .font(.caption)
                        Slider(value: $confirmationTimeout, in: 2.0...10.0, step: 0.5)
                    }
                }

                Section("Voice Detection") {
                    VStack(alignment: .leading) {
                        Text("Silence Sensitivity: \(silenceThreshold, specifier: "%.3f")")
                            .font(.caption)
                        Slider(value: $silenceThreshold, in: 0.001...0.05, step: 0.001)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        EvenClawConfig.openClawHost = openClawHost
        EvenClawConfig.openClawPort = Int(openClawPort) ?? 18789
        EvenClawConfig.openClawToken = openClawToken
        EvenClawConfig.openAIKey = openAIKey
        EvenClawConfig.ttsEnabled = ttsEnabled
        EvenClawConfig.ttsVoice = ttsVoice
        EvenClawConfig.silenceThreshold = Float(silenceThreshold)
        EvenClawConfig.wakeWordEnabled = wakeWordEnabled
        EvenClawConfig.wakeWordPhrase = wakeWordPhrase
        EvenClawConfig.liveDictationEnabled = liveDictationEnabled
        EvenClawConfig.confirmationTimeout = confirmationTimeout
    }
}
