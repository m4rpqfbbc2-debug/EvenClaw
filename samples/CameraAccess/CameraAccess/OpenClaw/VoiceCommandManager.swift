// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// VoiceCommandManager.swift
// Orchestrates: Mic → Whisper → OpenClaw → HUD notification + TTS.

import Foundation
import Combine

enum AppConnectionStatus: Equatable {
    case disconnected
    case checking
    case ready
    case error(String)
}

@MainActor
class VoiceCommandManager: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var isProcessing = false
    @Published var lastTranscription = ""
    @Published var lastResponse = ""
    @Published var connectionStatus: AppConnectionStatus = .disconnected
    @Published var openClawConnected = false
    @Published var glassesConnected = false

    // MARK: - Dependencies

    let audioManager = AudioManager()
    let whisperService = WhisperService()
    let openClawBridge = OpenClawBridge()
    let notificationBridge = NotificationBridge.shared
    let ttsService = TTSService()
    let glassesProvider: GlassesProvider

    // MARK: - VAD

    private var silenceTimer: Timer?
    private var vadTask: Task<Void, Never>?
    private var hasDetectedSpeech = false

    // MARK: - Init

    init(glassesProvider: GlassesProvider = NotificationProvider()) {
        self.glassesProvider = glassesProvider
    }

    // MARK: - Setup

    func setup() async {
        // Request notification permission
        await notificationBridge.requestPermission()

        // Connect glasses
        do {
            try await glassesProvider.connect()
            glassesConnected = glassesProvider.connectionState == .connected
        } catch {
            NSLog("[VCM] Glasses connection failed: %@", error.localizedDescription)
        }

        // Check OpenClaw
        await openClawBridge.checkConnection()
        openClawConnected = openClawBridge.connectionState == .connected
        connectionStatus = openClawConnected ? .ready : .error("OpenClaw unreachable")

        // Setup audio session
        do {
            try audioManager.setupAudioSession()
        } catch {
            connectionStatus = .error("Audio setup failed")
        }
    }

    // MARK: - Listening

    func toggleListening() {
        if isListening {
            stopListeningAndProcess()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening, !isProcessing else { return }

        do {
            try audioManager.startCapture()
            isListening = true
            hasDetectedSpeech = false
            lastTranscription = ""
            lastResponse = ""
            NSLog("[VCM] Listening started")

            // Start VAD monitoring
            startVAD()
        } catch {
            NSLog("[VCM] Failed to start capture: %@", error.localizedDescription)
            connectionStatus = .error("Mic error: \(error.localizedDescription)")
        }
    }

    func stopListeningAndProcess() {
        guard isListening else { return }

        stopVAD()
        let pcmData = audioManager.stopCapture()
        isListening = false

        // Need at least 0.5 seconds of audio (16000 samples/s * 2 bytes * 0.5s = 16000 bytes)
        guard pcmData.count > 16000 else {
            NSLog("[VCM] Audio too short (%d bytes), ignoring", pcmData.count)
            return
        }

        // Process the audio
        isProcessing = true
        Task {
            await processAudio(pcmData)
            isProcessing = false
        }
    }

    // MARK: - VAD (Voice Activity Detection)

    private func startVAD() {
        vadTask = Task { [weak self] in
            var silentFrames = 0
            let threshold = EvenClawConfig.silenceThreshold
            let requiredSilentFrames = Int(EvenClawConfig.silenceDuration * 10) // Check ~10x/sec

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self, self.isListening else { break }

                let rms = self.audioManager.currentRMS

                if rms > threshold {
                    self.hasDetectedSpeech = true
                    silentFrames = 0
                } else if self.hasDetectedSpeech {
                    silentFrames += 1
                    if silentFrames >= requiredSilentFrames {
                        NSLog("[VCM] Silence detected after speech, auto-stopping")
                        await MainActor.run {
                            self.stopListeningAndProcess()
                        }
                        break
                    }
                }
            }
        }
    }

    private func stopVAD() {
        vadTask?.cancel()
        vadTask = nil
    }

    // MARK: - Processing Pipeline

    private func processAudio(_ pcmData: Data) async {
        // Step 1: Convert to WAV
        let wavData = AudioManager.pcmToWAV(pcmData)
        NSLog("[VCM] WAV data: %d bytes", wavData.count)

        // Step 2: Transcribe with Whisper
        do {
            let transcription = try await whisperService.transcribe(audioData: wavData)
            guard !transcription.isEmpty else {
                NSLog("[VCM] Empty transcription")
                return
            }
            lastTranscription = transcription
            NSLog("[VCM] Transcribed: %@", transcription)
        } catch {
            NSLog("[VCM] Whisper error: %@", error.localizedDescription)
            lastResponse = "Transcription failed: \(error.localizedDescription)"
            return
        }

        // Step 3: Send to OpenClaw
        let (success, response) = await openClawBridge.sendMessage(lastTranscription)

        if success {
            lastResponse = response
            NSLog("[VCM] OpenClaw response: %@", String(response.prefix(200)))

            // Step 4: Display on HUD
            let hudText = HUDFormatter.formatResponse(response, maxChars: 100)
            let style = DisplayStyle(title: "EvenClaw", priority: .normal)
            do {
                try await glassesProvider.displayText(hudText, style: style)
            } catch {
                // Fallback to notification
                notificationBridge.pushToHUD(title: "EvenClaw", body: hudText)
            }

            // Step 5: TTS (optional)
            if EvenClawConfig.ttsEnabled {
                // Speak a concise version
                let spokenText = HUDFormatter.formatResponse(response, maxChars: 300)
                try? await ttsService.speak(spokenText)
            }
        } else {
            lastResponse = "Error: \(response)"
            notificationBridge.pushToHUD(title: "EvenClaw", body: "Error: \(response)")
        }
    }
}
