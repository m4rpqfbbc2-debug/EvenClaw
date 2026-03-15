// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// VoiceCommandManager.swift
// Phase 2: Gesture-driven pipeline. Mic only activates via state machine.
// No wake word by default, no silence-based auto-send.
// Double-tap (forceSend) is the only send trigger.

import Foundation
import Speech
import AVFoundation
import CoreMotion

// Legacy state enum for backwards compat with EvenClawController
enum AssistantState: Equatable {
    case idle
    case listening
    case waitingForTouchBar
    case recordingFromG2
    case processing
    case sending
    case error(String)
}

@MainActor
class VoiceCommandManager: ObservableObject {

    // MARK: - Published State

    @Published var state: AssistantState = .idle {
        didSet { onStateChange?(state) }
    }
    @Published var isRecording = false
    @Published var liveText = ""
    @Published var responseText = ""
    @Published var debugStatus = ""
    @Published var openClawConnected = false
    @Published var glassesConnected = false
    @Published var audioLevelHistory: [Float] = Array(repeating: 0, count: 30)
    @Published var wakeWordActive = false
    @Published var headGestureActive = false

    // MARK: - Dependencies

    let openClawBridge = OpenClawBridge()
    let glassesProvider: GlassesProvider
    weak var bleManager: G2BLEManager?
    // HeadGestureDetector removed from primary flow (Phase 2)
    // Stub properties for backwards compat with EvenClawController
    var headGestureDetectorIsActive: Bool { false }
    var headGestureDetectorSource: String { "none" }

    /// Called whenever state changes — used by EvenClawController for UI sync
    var onStateChange: ((AssistantState) -> Void)?

    /// Callback to display text on HUD — set by G2Sniffer
    var onHUDDisplay: ((String) async -> Void)?

    /// Callback when recording is force-sent (double-tap)
    var onRecordingComplete: ((String) -> Void)?

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()

    // MARK: - Init

    init(glassesProvider: GlassesProvider) {
        self.glassesProvider = glassesProvider
    }

    // MARK: - Setup

    func setup() async {
        NSLog("[VCM] setup() STARTED")

        // Request speech permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                NSLog("[VCM] Speech auth result: \(status.rawValue)")
                cont.resume()
            }
        }

        // Request mic permission
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                NSLog("[VCM] Mic permission: \(granted)")
                cont.resume()
            }
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

        // Glasses connection is handled by G2Sniffer
        glassesConnected = glassesProvider.connectionState == .connected

        NSLog("[VCM] setup() complete — gesture-driven mode")
    }

    // MARK: - Cancel / Reset

    func cancelCurrentOperation() {
        stopAudio()
        liveText = ""
        responseText = ""
        isRecording = false
        state = .idle
        NSLog("[VCM] Operation cancelled, reset to idle")
    }

    // MARK: - Start Listening (called by state machine or TouchBar)

    func startListening() {
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
        isRecording = true
        state = .listening

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frames) { sum += abs(data[i]) }
                let avg = sum / Float(frames)
                Task { @MainActor in
                    self?.audioLevelHistory.append(avg)
                    if (self?.audioLevelHistory.count ?? 0) > 30 {
                        self?.audioLevelHistory.removeFirst()
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("Mic failed: \(error.localizedDescription)")
            isRecording = false
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }

                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    self.showOnHUD(self.liveText)
                }

                if let error {
                    NSLog("[VCM] Recognition error: %@", error.localizedDescription)
                }
            }
        }

        showOnHUD("Listening...")
        NSLog("[VCM] Listening started (gesture-driven, no auto-send)")
    }

    // MARK: - Stop Listening

    func stopListening() {
        stopAudio()
        isRecording = false
        state = .idle
        NSLog("[VCM] Listening stopped")
    }

    // MARK: - Force Send (double-tap trigger)

    func forceSend() -> String {
        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudio()
        isRecording = false
        state = .sending
        NSLog("[VCM] Force send: \(text.prefix(80))")
        if !text.isEmpty {
            onRecordingComplete?(text)
        }
        return text
    }

    // MARK: - Send to AI

    func sendToAI(_ text: String) async -> String? {
        state = .processing
        showOnHUD("Thinking...")
        NSLog("[VCM] Sending to AI: %@", String(text.prefix(80)))

        let (success, response) = await openClawBridge.sendMessage(text)

        if success && !response.isEmpty && response != "No response from AI." {
            responseText = response
            state = .idle
            NSLog("[VCM] Response: %@", String(response.prefix(200)))
            return response
        } else {
            state = .error("No response")
            NSLog("[VCM] AI error: %@", response)
            return nil
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
        audioLevelHistory = Array(repeating: 0, count: 30)
    }

    // MARK: - HUD Display

    func showOnHUD(_ text: String) {
        NSLog("[VCM] showOnHUD: '\(text.prefix(80))'")
        if let onHUDDisplay {
            Task { await onHUDDisplay(text) }
            return
        }
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

    // MARK: - TouchBar Event Handler (legacy compat)

    func handleTouchBarEvent(_ subcmd: UInt8) {
        switch subcmd {
        case G2Constants.TouchBar.evenAIStart:
            NSLog("[VCM] TouchBar start — beginning to listen")
            if state != .listening {
                showOnHUD("Aisha listening...")
                startListening()
            }
        case G2Constants.TouchBar.evenAIStop:
            NSLog("[VCM] TouchBar stop")
            // Don't auto-send — wait for double-tap
        default:
            break
        }
    }

    // MARK: - BLE Manager

    func setBLEManager(_ manager: G2BLEManager) {
        bleManager = manager
        state = .waitingForTouchBar
    }

    func handleG2AudioData(_ data: Data) {
        // G2 audio routing — future use
    }
}
