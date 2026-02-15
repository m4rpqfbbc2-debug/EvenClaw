// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// VoiceCommandManager.swift
// Simple pipeline: Mic → Speech Recognition → OpenClaw → HUD

import Foundation
import Speech
import AVFoundation

enum AssistantState: Equatable {
    case idle
    case listening
    case sending
    case error(String)
}

@MainActor
class VoiceCommandManager: ObservableObject {

    // MARK: - Published State

    @Published var state: AssistantState = .idle
    @Published var openClawConnected = false
    @Published var glassesConnected = false
    @Published var liveText = ""
    @Published var responseText = ""
    @Published var debugStatus = ""

    // MARK: - Dependencies

    let openClawBridge = OpenClawBridge()
    let glassesProvider: GlassesProvider

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()

    // MARK: - Silence Detection

    private var silenceTimer: Timer?
    private var lastTranscriptionTime: Date?
    private let silenceThreshold: TimeInterval = 2.0 // seconds of silence before auto-send

    // MARK: - Init

    init(glassesProvider: GlassesProvider) {
        self.glassesProvider = glassesProvider
    }

    // MARK: - Setup

    func setup() async {
        // Request speech permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }

        // Request mic permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in cont.resume() }
        }

        // Setup audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            debugStatus = "Audio setup failed: \(error.localizedDescription)"
        }

        // Check OpenClaw
        debugStatus = "Connecting to \(openClawBridge.baseURL)..."
        await openClawBridge.checkConnection()
        openClawConnected = openClawBridge.connectionState == .connected
        if openClawConnected {
            debugStatus = "OpenClaw ✅"
        } else if case .unreachable(let msg) = openClawBridge.connectionState {
            debugStatus = "OpenClaw ❌ \(msg)"
        }

        // Connect glasses
        debugStatus += "\nScanning for G2..."
        do {
            try await glassesProvider.connect()
            glassesConnected = glassesProvider.connectionState == .connected
            debugStatus += "\nGlasses ✅"
        } catch {
            debugStatus += "\nGlasses ❌ \(error.localizedDescription)"
        }

        // Show ready on HUD if glasses connected
        if glassesConnected {
            showOnHUD("EvenClaw ready")
        }
    }

    // MARK: - Mic Toggle

    func toggleMic() {
        switch state {
        case .idle, .error:
            startListening()
        case .listening:
            stopAndSend()
        case .sending:
            break // wait
        }
    }

    // MARK: - Start Listening

    private func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognition unavailable")
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            state = .error("Speech permission denied")
            return
        }

        liveText = ""
        responseText = ""
        state = .listening

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("Mic failed: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.state == .listening else { return }

                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    self.lastTranscriptionTime = Date()

                    // Show live text on HUD
                    self.showOnHUD(self.liveText)

                    // Reset silence timer
                    self.resetSilenceTimer()
                }

                if let error {
                    NSLog("[VCM] Recognition error: %@", error.localizedDescription)
                    // Don't error out — partial results might have been enough
                    if self.liveText.isEmpty {
                        self.state = .error("No speech detected")
                        self.stopAudio()
                    }
                }
            }
        }

        // Start silence timer
        resetSilenceTimer()
        showOnHUD("Listening...")
        NSLog("[VCM] Listening started")
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening, !self.liveText.isEmpty else { return }
                self.stopAndSend()
            }
        }
    }

    // MARK: - Stop & Send

    private func stopAndSend() {
        guard state == .listening else { return }
        silenceTimer?.invalidate()
        stopAudio()

        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .idle
            return
        }

        state = .sending
        showOnHUD("Thinking...")
        NSLog("[VCM] Sending: %@", text)

        // Animate "Thinking..." on HUD
        var dots = 0
        let animTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, self.state == .sending else { timer.invalidate(); return }
                dots = (dots + 1) % 4
                self.showOnHUD("Thinking" + String(repeating: ".", count: dots + 1))
            }
        }

        Task {
            let (success, response) = await openClawBridge.sendMessage(text)
            animTimer.invalidate()

            if success {
                responseText = response
                showOnHUD(response)
                NSLog("[VCM] Response: %@", String(response.prefix(200)))

                // Auto-clear after 15 seconds
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if state == .sending {
                    showOnHUD("EvenClaw ready")
                }
            } else {
                state = .error("Failed: \(response)")
                showOnHUD("Error")
            }

            state = .idle
        }
    }

    // MARK: - Audio Cleanup

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - HUD Display

    private func showOnHUD(_ text: String) {
        guard glassesConnected else { return }
        let style = DisplayStyle(title: "EvenClaw", priority: .normal)
        Task {
            do {
                try await glassesProvider.displayText(text, style: style)
            } catch {
                NSLog("[VCM] HUD display failed: %@", error.localizedDescription)
            }
        }
    }
}
