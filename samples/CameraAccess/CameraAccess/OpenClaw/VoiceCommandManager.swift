// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// VoiceCommandManager.swift
// Orchestrates: G2 Conversate → Send Confirmation → Processing → Response
//
// PRIMARY: G2 Conversate BLE hijack (user long-presses left TouchBar)
// FALLBACK: iPhone mic → Whisper (when glasses not connected)
//
// State Machine:
// idle (waiting for TouchBar long-press or mic button)
//   → Conversate packets start arriving (or mic button pressed)
// listening (live dictation on HUD from partial transcripts)
//   → is_final=true received (or silence on phone mic)
// confirming (HUD shows final text + "Tap to send")
//   → tap/timeout = send, double-tap = cancel
// processing (HUD shows "Thinking..." animation)  
//   → response received
// responding (HUD shows AI response)
//   → auto-clear → back to idle

import Foundation
import Combine
import AVFoundation

// MARK: - App State

enum VoiceAssistantState: Equatable {
    case idle              // Waiting for TouchBar long-press or mic button
    case listening         // Live dictation active (G2 partial transcripts or phone mic)
    case confirming        // Show final text + "Tap to send"
    case processing        // "Thinking..." animation
    case responding        // Show AI response + TTS
    case error(String)     // Error state
}

enum AppConnectionStatus: Equatable {
    case disconnected
    case checking
    case ready
    case error(String)
}

enum TranscriptionSource {
    case g2Conversate      // Primary: G2 BLE Conversate service
    case phoneMic          // Fallback: iPhone mic → Whisper
}

@MainActor
class VoiceCommandManager: ObservableObject {

    // MARK: - Published State

    @Published var currentState: VoiceAssistantState = .idle
    @Published var isListening = false
    @Published var isProcessing = false
    @Published var lastTranscription = ""
    @Published var lastResponse = ""
    @Published var connectionStatus: AppConnectionStatus = .disconnected
    @Published var openClawConnected = false
    @Published var glassesConnected = false
    @Published var liveTranscriptionText = ""
    @Published var debugStatus = ""
    @Published var currentTranscriptionSource: TranscriptionSource = .g2Conversate

    // MARK: - Dependencies

    let audioManager = AudioManager()
    let whisperService = WhisperService()
    let openClawBridge = OpenClawBridge()
    let notificationBridge = NotificationBridge.shared
    let ttsService = TTSService()
    let glassesProvider: GlassesProvider

    // MARK: - Timers & Tasks

    private var confirmationTimer: Timer?
    private var processingAnimationTimer: Timer?
    private var responseDisplayTimer: Timer?
    private var vadTask: Task<Void, Never>?

    // MARK: - State Tracking

    private var hasDetectedSpeech = false
    private var currentAnimationStep = 0
    private var responsePage = 0
    private var responsePages: [String] = []

    // MARK: - Init

    init(glassesProvider: GlassesProvider = NotificationProvider()) {
        self.glassesProvider = glassesProvider
        
        // Set up gesture callback
        self.glassesProvider.onGesture = { [weak self] gesture in
            Task { @MainActor in
                self?.handleGesture(gesture)
            }
        }
        
        // Set up voice transcription callback (G2 Conversate)
        self.glassesProvider.onVoiceTranscription = { [weak self] text, isFinal in
            Task { @MainActor in
                self?.handleVoiceTranscription(text, isFinal: isFinal)
            }
        }
    }

    // MARK: - Setup

    func setup() async {
        // Request notification permission
        await notificationBridge.requestPermission()

        // Check OpenClaw first
        debugStatus = "→ \(openClawBridge.baseURL)/v1/..."
        await openClawBridge.checkConnection()
        openClawConnected = openClawBridge.connectionState == .connected
        if openClawConnected {
            debugStatus = "OpenClaw ✅ connected"
        } else if case .unreachable(let msg) = openClawBridge.connectionState {
            debugStatus = "OpenClaw ❌ \(msg)"
        } else {
            debugStatus = "OpenClaw ❌ not configured"
        }
        connectionStatus = openClawConnected ? .ready : .error("OpenClaw unreachable")

        // Connect glasses
        debugStatus += "\nScanning for G2..."
        do {
            try await glassesProvider.connect()
            glassesConnected = glassesProvider.connectionState == .connected
            debugStatus += "\nGlasses ✅ connected"
        } catch {
            NSLog("[VCM] Glasses connection failed: %@", error.localizedDescription)
            debugStatus += "\nGlasses ❌ \(error.localizedDescription)"
        }

        // Setup audio session for fallback phone mic
        do {
            try audioManager.setupAudioSession()
        } catch {
            connectionStatus = .error("Audio setup failed")
        }

        // Display initial status
        if glassesConnected {
            displayOnHUD("Ready - long-press left TouchBar to speak")
        } else {
            displayOnHUD("Ready - tap mic button to speak")
        }
    }

    // MARK: - State Machine

    private func setState(_ newState: VoiceAssistantState) {
        let oldState = currentState
        currentState = newState
        
        // Update legacy published properties for UI compatibility
        isListening = (newState == .listening)
        isProcessing = (newState == .processing)
        
        NSLog("[VCM] State: %@ → %@", String(describing: oldState), String(describing: newState))
        
        // Handle state transitions
        handleStateTransition(from: oldState, to: newState)
    }

    private func handleStateTransition(from oldState: VoiceAssistantState, to newState: VoiceAssistantState) {
        // Clean up previous state
        switch oldState {
        case .listening:
            stopPhoneMicIfActive()
        case .confirming:
            confirmationTimer?.invalidate()
        case .processing:
            processingAnimationTimer?.invalidate()
        case .responding:
            responseDisplayTimer?.invalidate()
        default:
            break
        }
        
        // Set up new state
        switch newState {
        case .idle:
            clearHUD()
            liveTranscriptionText = ""
            if glassesConnected {
                displayOnHUD("Ready - long-press left TouchBar to speak")
            } else {
                displayOnHUD("Ready - tap mic button to speak")
            }
        case .listening:
            if currentTranscriptionSource == .g2Conversate {
                displayOnHUD("Listening via glasses...")
            } else {
                displayOnHUD("Listening via phone...")
                startPhoneMicCapture()
            }
        case .confirming:
            displayConfirmationOnHUD()
            startConfirmationTimer()
        case .processing:
            displayOnHUD("Thinking.")
            startProcessingAnimation()
        case .responding:
            displayResponseOnHUD()
            startResponseTimer()
        case .error(let message):
            displayOnHUD("Error: \(message)")
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                setState(.idle)
            }
        }
    }

    // MARK: - G2 Conversate Transcription (Primary)

    private func handleVoiceTranscription(_ text: String, isFinal: Bool) {
        guard glassesConnected else { return }
        
        NSLog("[VCM] G2 transcript: '\(text)' (final: \(isFinal))")
        
        if currentState == .idle && !text.isEmpty {
            // Start of new transcription session
            currentTranscriptionSource = .g2Conversate
            setState(.listening)
        }
        
        if currentState == .listening {
            liveTranscriptionText = text
            
            // Update HUD with live transcription
            if !text.isEmpty {
                let hudText = HUDFormatter.formatResponse(text, maxChars: 200)
                displayOnHUD(hudText)
            }
            
            if isFinal && !text.isEmpty {
                // Final transcription received
                lastTranscription = text
                setState(.confirming)
            }
        }
    }

    // MARK: - Phone Mic Transcription (Fallback)

    private func startPhoneMicCapture() {
        guard !glassesConnected || currentTranscriptionSource == .phoneMic else { return }
        
        do {
            try audioManager.startCapture()
            hasDetectedSpeech = false
            liveTranscriptionText = ""
            startVAD()
            NSLog("[VCM] Phone mic capture started")
        } catch {
            setState(.error("Failed to start phone mic: \(error.localizedDescription)"))
        }
    }

    private func stopPhoneMicIfActive() {
        guard currentTranscriptionSource == .phoneMic else { return }
        
        let pcmData = audioManager.stopCapture()
        stopVAD()
        
        // Process with Whisper if we have enough audio
        if pcmData.count > 16000 { // ~1 second at 16kHz
            Task {
                await processPhoneMicAudio(pcmData)
            }
        }
    }

    private func processPhoneMicAudio(_ pcmData: Data) async {
        // Convert to WAV and transcribe with Whisper
        let wavData = AudioManager.pcmToWAV(pcmData)
        NSLog("[VCM] Processing phone mic WAV: %d bytes", wavData.count)

        do {
            let transcription = try await whisperService.transcribe(audioData: wavData)
            guard !transcription.isEmpty else {
                NSLog("[VCM] Empty phone mic transcription")
                setState(.idle)
                return
            }
            
            lastTranscription = transcription
            NSLog("[VCM] Phone mic transcribed: %@", transcription)
            setState(.confirming)
        } catch {
            NSLog("[VCM] Phone mic Whisper error: %@", error.localizedDescription)
            setState(.error("Phone mic transcription failed"))
        }
    }

    // MARK: - VAD (Voice Activity Detection) - Phone Mic Only

    private func startVAD() {
        vadTask = Task { [weak self] in
            var silentFrames = 0
            let threshold = EvenClawConfig.silenceThreshold
            let requiredSilentFrames = Int(EvenClawConfig.silenceDuration * 10) // Check ~10x/sec

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self, self.currentState == .listening, 
                      self.currentTranscriptionSource == .phoneMic else { break }

                let rms = self.audioManager.currentRMS

                if rms > threshold {
                    self.hasDetectedSpeech = true
                    silentFrames = 0
                } else if self.hasDetectedSpeech {
                    silentFrames += 1
                    if silentFrames >= requiredSilentFrames {
                        NSLog("[VCM] Phone mic silence detected")
                        await MainActor.run {
                            self.setState(.confirming)
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

    // MARK: - Confirmation State

    private func displayConfirmationOnHUD() {
        let confirmText = "\(lastTranscription)\n\nTap to send"
        displayOnHUD(confirmText)
    }

    private func startConfirmationTimer() {
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: EvenClawConfig.confirmationTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.sendTranscription()
            }
        }
    }

    // MARK: - Processing Animation

    private func startProcessingAnimation() {
        currentAnimationStep = 0
        processingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProcessingAnimation()
            }
        }
    }

    private func updateProcessingAnimation() {
        let dots = String(repeating: ".", count: (currentAnimationStep % 3) + 1)
        displayOnHUD("Thinking\(dots)")
        currentAnimationStep += 1
    }

    // MARK: - Response Display

    private func displayResponseOnHUD() {
        responsePages = HUDFormatter.formatResponse(lastResponse, maxChars: 200).components(separatedBy: "\n\n")
        responsePage = 0
        showCurrentResponsePage()
        
        // Play TTS if enabled
        if EvenClawConfig.ttsEnabled {
            let spokenText = HUDFormatter.formatResponse(lastResponse, maxChars: 300)
            Task {
                try? await ttsService.speak(spokenText)
            }
        }
    }

    private func showCurrentResponsePage() {
        guard responsePage < responsePages.count else { return }
        let pageText = responsePages[responsePage]
        let indicator = responsePages.count > 1 ? " (\(responsePage + 1)/\(responsePages.count))" : ""
        displayOnHUD(pageText + indicator)
    }

    private func startResponseTimer() {
        responseDisplayTimer = Timer.scheduledTimer(withTimeInterval: EvenClawConfig.responseDisplayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.setState(.idle)
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleGesture(_ gesture: GlassesGesture) {
        NSLog("[VCM] Gesture received: %@", String(describing: gesture))
        
        switch currentState {
        case .confirming:
            switch gesture {
            case .tap:
                sendTranscription()
            case .doubleTap:
                setState(.idle)
            default:
                break
            }
            
        case .responding:
            switch gesture {
            case .tap, .swipeForward:
                if responsePage < responsePages.count - 1 {
                    responsePage += 1
                    showCurrentResponsePage()
                } else {
                    setState(.idle)
                }
            case .swipeBackward:
                if responsePage > 0 {
                    responsePage -= 1
                    showCurrentResponsePage()
                }
            case .doubleTap:
                setState(.idle)
            default:
                break
            }
            
        default:
            break
        }
    }

    // MARK: - Glasses Conversate Input (PRIMARY PATH)

    /// Handle transcription from G2's Conversate service (0x0B-20).
    /// The glasses do the speech recognition — we just get text + is_final.
    /// This fires when user long-presses left TouchBar and speaks.
    private func handleGlassesTranscription(_ text: String, isFinal: Bool) {
        NSLog("[VCM] G2 Conversate: \"%@\" (final=%d)", text, isFinal ? 1 : 0)

        if currentState == .idle {
            // First transcript packet — transition to listening
            setState(.listening)
        }

        guard currentState == .listening else { return }

        // Update live transcription on phone UI
        liveTranscriptionText = text
        lastTranscription = text

        // Push live text to HUD
        displayOnHUD(text)

        if isFinal {
            // G2 says user is done speaking — go to confirmation
            NSLog("[VCM] G2 final transcript, entering confirmation")
            setState(.confirming)
        }
    }

    // MARK: - Processing Pipeline

    private func sendTranscription() {
        guard !lastTranscription.isEmpty else {
            setState(.idle)
            return
        }
        
        setState(.processing)
        
        Task {
            let (success, response) = await openClawBridge.sendMessage(lastTranscription)
            
            if success {
                lastResponse = response
                NSLog("[VCM] OpenClaw response: %@", String(response.prefix(200)))
                setState(.responding)
            } else {
                setState(.error("OpenClaw error: \(response)"))
            }
        }
    }

    // MARK: - Manual Controls (Fallback Phone Mic)

    func toggleListening() {
        switch currentState {
        case .idle:
            // Force phone mic mode (fallback)
            currentTranscriptionSource = .phoneMic
            setState(.listening)
        case .listening:
            if currentTranscriptionSource == .phoneMic {
                setState(.confirming)
            }
            // If G2 Conversate is active, let it handle completion naturally
        case .confirming:
            sendTranscription()
        case .responding:
            setState(.idle)
        default:
            break
        }
    }

    // MARK: - HUD Display

    private func displayOnHUD(_ text: String) {
        let style = DisplayStyle(title: "EvenClaw", priority: .normal)
        Task {
            do {
                try await glassesProvider.displayText(text, style: style)
            } catch {
                // Fallback to notification
                notificationBridge.pushToHUD(title: "EvenClaw", body: text)
            }
        }
    }

    private func clearHUD() {
        Task {
            do {
                try await glassesProvider.clearDisplay()
            } catch {
                NSLog("[VCM] Failed to clear HUD: %@", error.localizedDescription)
            }
        }
    }
}