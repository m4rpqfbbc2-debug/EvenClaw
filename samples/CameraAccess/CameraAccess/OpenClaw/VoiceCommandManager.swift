// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// VoiceCommandManager.swift
// Orchestrates: Wake Word → Live Dictation → Send Confirmation → Processing → Response
//
// State Machine:
// idle (wake word listening) 
//   → "Hey Aisha" detected or mic button pressed
// listening (live dictation, HUD showing words)
//   → silence detected  
// confirming (HUD shows text + "Tap to send")
//   → tap/timeout = send, double-tap = cancel back to idle
// processing (HUD shows "Thinking..." animation)
//   → response received
// responding (HUD shows AI response, TTS playing)
//   → auto-clear after 15s or gesture → back to idle

import Foundation
import Combine
import Speech
import AVFoundation

// MARK: - App State

enum VoiceAssistantState: Equatable {
    case idle              // Wake word listening
    case listening         // Live dictation active
    case confirming        // Show transcription + "Tap to send"
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

    // MARK: - Dependencies

    let audioManager = AudioManager()
    let whisperService = WhisperService()
    let openClawBridge = OpenClawBridge()
    let notificationBridge = NotificationBridge.shared
    let ttsService = TTSService()
    let glassesProvider: GlassesProvider

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var wakeWordTask: SFSpeechRecognitionTask?
    private var wakeWordRequest: SFSpeechAudioBufferRecognitionRequest?

    // MARK: - Timers & Tasks

    private var confirmationTimer: Timer?
    private var processingAnimationTimer: Timer?
    private var responseDisplayTimer: Timer?
    private var hudUpdateTimer: Timer?
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
    }

    // MARK: - Setup

    func setup() async {
        // Request speech recognition permission
        await requestSpeechPermission()
        
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

        // Start wake word detection if enabled
        if EvenClawConfig.wakeWordEnabled {
            await startWakeWordDetection()
        }
    }

    // MARK: - Speech Permission

    private func requestSpeechPermission() async {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume()
            }
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
            stopLiveRecognition()
            stopHUDUpdates()
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
            if EvenClawConfig.wakeWordEnabled {
                Task { await startWakeWordDetection() }
            }
        case .listening:
            startLiveRecognition()
            startHUDUpdates()
            displayOnHUD("Listening...")
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

    // MARK: - Wake Word Detection

    private func startWakeWordDetection() async {
        guard currentState == .idle,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            NSLog("[VCM] Wake word detection unavailable")
            return
        }

        do {
            wakeWordRequest = SFSpeechAudioBufferRecognitionRequest()
            wakeWordRequest?.shouldReportPartialResults = true
            
            wakeWordTask = speechRecognizer.recognitionTask(with: wakeWordRequest!) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleWakeWordResult(result, error: error)
                }
            }
            
            // Set up audio buffer callback
            audioManager.onAudioBuffer = { [weak self] buffer in
                self?.wakeWordRequest?.append(buffer)
            }
            
            // Start low-level audio capture for wake word detection
            try audioManager.startCapture()
            
            NSLog("[VCM] Wake word detection started")
        } catch {
            NSLog("[VCM] Failed to start wake word detection: %@", error.localizedDescription)
        }
    }

    private func handleWakeWordResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard currentState == .idle else { return }
        
        if let result = result {
            let transcription = result.bestTranscription.formattedString.lowercased()
            if transcription.contains(EvenClawConfig.wakeWordPhrase.lowercased()) {
                NSLog("[VCM] Wake word detected: %@", transcription)
                stopWakeWordDetection()
                setState(.listening)
            }
        }
        
        if let error = error {
            NSLog("[VCM] Wake word recognition error: %@", error.localizedDescription)
        }
    }

    private func stopWakeWordDetection() {
        wakeWordTask?.cancel()
        wakeWordTask = nil
        wakeWordRequest = nil
        audioManager.onAudioBuffer = nil
        let _ = audioManager.stopCapture()
    }

    // MARK: - Live Recognition

    private func startLiveRecognition() {
        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            setState(.error("Speech recognition unavailable"))
            return
        }

        do {
            hasDetectedSpeech = false
            liveTranscriptionText = ""
            
            // Setup speech recognition
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest?.shouldReportPartialResults = true
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleLiveRecognitionResult(result, error: error)
                }
            }
            
            // Set up audio buffer callback for live recognition
            audioManager.onAudioBuffer = { [weak self] buffer in
                self?.recognitionRequest?.append(buffer)
            }
            
            // Start audio capture for both speech recognition and VAD (reuse if already running)
            if !audioManager.isCapturing {
                try audioManager.startCapture()
            }
            
            // Start VAD for silence detection
            startVAD()
            
            NSLog("[VCM] Live recognition started")
        } catch {
            setState(.error("Failed to start listening: \(error.localizedDescription)"))
        }
    }

    private func handleLiveRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard currentState == .listening else { return }
        
        if let result = result {
            liveTranscriptionText = result.bestTranscription.formattedString
            hasDetectedSpeech = true
        }
        
        if let error = error {
            NSLog("[VCM] Live recognition error: %@", error.localizedDescription)
        }
    }

    private func stopLiveRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioManager.onAudioBuffer = nil
        
        // Stop audio capture and get final PCM data
        let pcmData = audioManager.stopCapture()
        lastTranscription = liveTranscriptionText
        
        stopVAD()
    }

    // MARK: - VAD (Voice Activity Detection)

    private func startVAD() {
        vadTask = Task { [weak self] in
            var silentFrames = 0
            let threshold = EvenClawConfig.silenceThreshold
            let requiredSilentFrames = Int(EvenClawConfig.silenceDuration * 10) // Check ~10x/sec

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self, self.currentState == .listening else { break }

                let rms = self.audioManager.currentRMS

                if rms > threshold {
                    self.hasDetectedSpeech = true
                    silentFrames = 0
                } else if self.hasDetectedSpeech {
                    silentFrames += 1
                    if silentFrames >= requiredSilentFrames {
                        NSLog("[VCM] Silence detected after speech")
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

    // MARK: - HUD Updates

    private func startHUDUpdates() {
        hudUpdateTimer = Timer.scheduledTimer(withTimeInterval: EvenClawConfig.hudUpdateRate, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHUDWithLiveTranscription()
            }
        }
    }

    private func stopHUDUpdates() {
        hudUpdateTimer?.invalidate()
        hudUpdateTimer = nil
    }

    private func updateHUDWithLiveTranscription() {
        guard currentState == .listening,
              !liveTranscriptionText.isEmpty else { return }
        
        let hudText = HUDFormatter.formatResponse(liveTranscriptionText, maxChars: 200)
        displayOnHUD(hudText)
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

    // MARK: - Manual Controls

    func toggleListening() {
        switch currentState {
        case .idle:
            setState(.listening)
        case .listening:
            setState(.confirming)
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