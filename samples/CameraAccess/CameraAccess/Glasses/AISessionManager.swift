// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// AISessionManager.swift
//
// Orchestrates the full AI pipeline for EvenClaw:
//   Voice (mic) → Gemini Live → Tool calls → OpenClaw → Response → HUD
//
// This manager wires together:
//   - GlassesProvider (display output)
//   - GeminiLiveService (AI backbone)
//   - OpenClawBridge (agentic tool execution)
//   - AudioManager (mic capture + playback)
//   - IPhoneCameraManager (video frames for Gemini vision)
//
// The key insight: video source is always iPhone (G2 has no camera),
// but display output routes through the glasses provider.
//

import Foundation
import UIKit

/// Manages the full AI session lifecycle with glasses integration.
@MainActor
class AISessionManager: ObservableObject {

    // MARK: - Published State

    @Published var isActive: Bool = false
    @Published var connectionState: GeminiConnectionState = .disconnected
    @Published var isModelSpeaking: Bool = false
    @Published var userTranscript: String = ""
    @Published var aiTranscript: String = ""
    @Published var toolCallStatus: ToolCallStatus = .idle
    @Published var openClawConnectionState: OpenClawConnectionState = .notConfigured
    @Published var glassesConnectionState: GlassesConnectionState = .disconnected
    @Published var errorMessage: String?

    // MARK: - Dependencies

    let glassesProvider: GlassesProvider
    private let geminiService = GeminiLiveService()
    private let openClawBridge = OpenClawBridge()
    private let audioManager = AudioManager()
    private var iPhoneCamera: IPhoneCameraManager?
    private var toolCallRouter: ToolCallRouter?
    private var stateObservation: Task<Void, Never>?
    private var lastVideoFrameTime: Date = .distantPast

    /// Maximum characters for the current glasses display
    private var displayMaxChars: Int {
        glassesProvider.displayCapability.maxChars ?? HUDFormatter.notificationLimit
    }

    // MARK: - Init

    /// Create a session manager with a specific glasses provider.
    ///
    /// - Parameter glassesProvider: The glasses hardware to route display output to.
    ///   Use `PhoneOnlyProvider()` for no glasses, `NotificationProvider()` for ANCS,
    ///   or `EvenG2Provider()` for native SDK (when available).
    init(glassesProvider: GlassesProvider) {
        self.glassesProvider = glassesProvider
    }

    // MARK: - Session Lifecycle

    /// Start the full AI session: connect glasses, start Gemini, begin capture.
    func startSession() async {
        guard !isActive else { return }
        guard GeminiConfig.isConfigured else {
            errorMessage = "Gemini API key not configured"
            return
        }

        isActive = true

        // Step 1: Connect glasses provider
        do {
            try await glassesProvider.connect()
            glassesConnectionState = glassesProvider.connectionState
            NSLog("[AISession] Glasses connected: %@", String(describing: type(of: glassesProvider)))
        } catch {
            // Non-fatal — we can still operate without glasses display
            NSLog("[AISession] Glasses connection failed (non-fatal): %@", error.localizedDescription)
            glassesConnectionState = glassesProvider.connectionState
        }

        // Step 2: Wire audio callbacks
        audioManager.onAudioCaptured = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                // Mute mic while model speaks (iPhone mode — prevent echo)
                if self.geminiService.isModelSpeaking { return }
                self.geminiService.sendAudio(data: data)
            }
        }

        geminiService.onAudioReceived = { [weak self] data in
            self?.audioManager.playAudio(data: data)
        }

        geminiService.onInterrupted = { [weak self] in
            self?.audioManager.stopPlayback()
        }

        // Step 3: Wire transcription → HUD display
        geminiService.onInputTranscription = { [weak self] text in
            guard let self else { return }
            Task { @MainActor in
                self.userTranscript += text
                self.aiTranscript = ""
            }
        }

        geminiService.onOutputTranscription = { [weak self] text in
            guard let self else { return }
            Task { @MainActor in
                self.aiTranscript += text
            }
        }

        geminiService.onTurnComplete = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // Display the final AI response on glasses HUD
                if !self.aiTranscript.isEmpty {
                    await self.displayOnGlasses(self.aiTranscript)
                }
                self.userTranscript = ""
            }
        }

        geminiService.onDisconnected = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                guard self.isActive else { return }
                self.stopSession()
                self.errorMessage = "Connection lost: \(reason ?? "Unknown")"
            }
        }

        // Step 4: Wire tool calls → OpenClaw → HUD
        await openClawBridge.checkConnection()
        openClawBridge.resetSession()
        toolCallRouter = ToolCallRouter(bridge: openClawBridge)

        geminiService.onToolCall = { [weak self] toolCall in
            guard let self else { return }
            Task { @MainActor in
                // Show "working" indicator on HUD
                await self.displayOnGlasses("Working on it…", priority: .low)

                for call in toolCall.functionCalls {
                    self.toolCallRouter?.handleToolCall(call) { [weak self] response in
                        self?.geminiService.sendToolResponse(response)

                        // Display tool result on HUD
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            // Extract task from function call args
                            let task = call.args["task"] as? String ?? ""
                            if case .success(let content) = self.openClawBridge.lastToolCallStatus == .completed(call.name) ? ToolResult.success("") : .success("") {
                                // The actual result display happens when Gemini speaks the response
                                _ = content
                            }
                        }
                    }
                }
            }
        }

        geminiService.onToolCallCancellation = { [weak self] cancellation in
            guard let self else { return }
            Task { @MainActor in
                self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
            }
        }

        // Step 5: Start state observation
        stateObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                self.connectionState = self.geminiService.connectionState
                self.isModelSpeaking = self.geminiService.isModelSpeaking
                self.toolCallStatus = self.openClawBridge.lastToolCallStatus
                self.openClawConnectionState = self.openClawBridge.connectionState
                self.glassesConnectionState = self.glassesProvider.connectionState
            }
        }

        // Step 6: Setup audio (always iPhone mode for G2)
        do {
            try audioManager.setupAudioSession(useIPhoneMode: true)
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            isActive = false
            return
        }

        // Step 7: Connect to Gemini
        let setupOk = await geminiService.connect()
        if !setupOk {
            if case .error(let err) = geminiService.connectionState {
                errorMessage = err
            } else {
                errorMessage = "Failed to connect to Gemini"
            }
            geminiService.disconnect()
            stateObservation?.cancel()
            isActive = false
            connectionState = .disconnected
            return
        }

        // Step 8: Start mic capture
        do {
            try audioManager.startCapture()
        } catch {
            errorMessage = "Mic capture failed: \(error.localizedDescription)"
            geminiService.disconnect()
            stateObservation?.cancel()
            isActive = false
            connectionState = .disconnected
            return
        }

        // Step 9: Start iPhone camera (always — G2 has no camera)
        startIPhoneCamera()

        NSLog("[AISession] Full session started")
    }

    /// Stop the AI session and clean up.
    func stopSession() {
        toolCallRouter?.cancelAll()
        toolCallRouter = nil
        audioManager.stopCapture()
        geminiService.disconnect()
        stopIPhoneCamera()
        glassesProvider.disconnect()
        stateObservation?.cancel()
        stateObservation = nil

        isActive = false
        connectionState = .disconnected
        isModelSpeaking = false
        userTranscript = ""
        aiTranscript = ""
        toolCallStatus = .idle
        glassesConnectionState = .disconnected

        NSLog("[AISession] Session stopped")
    }

    // MARK: - Video (iPhone Camera)

    private func startIPhoneCamera() {
        let camera = IPhoneCameraManager()
        camera.onFrameCaptured = { [weak self] image in
            Task { @MainActor [weak self] in
                self?.sendVideoFrameIfThrottled(image: image)
            }
        }
        camera.start()
        iPhoneCamera = camera
        NSLog("[AISession] iPhone camera started")
    }

    private func stopIPhoneCamera() {
        iPhoneCamera?.stop()
        iPhoneCamera = nil
    }

    /// Throttle video frames to ~1fps for Gemini.
    private func sendVideoFrameIfThrottled(image: UIImage) {
        guard isActive, connectionState == .ready else { return }
        let now = Date()
        guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
        lastVideoFrameTime = now
        geminiService.sendVideoFrame(image: image)
    }

    // MARK: - Display Output

    /// Format and display text on the glasses HUD.
    private func displayOnGlasses(_ text: String, priority: DisplayPriority = .normal) async {
        guard glassesProvider.displayCapability != .none else { return }

        let formatted = HUDFormatter.formatResponse(text, maxChars: displayMaxChars)
        let style = DisplayStyle(title: "EvenClaw", priority: priority)

        do {
            try await glassesProvider.displayText(formatted, style: style)
        } catch {
            NSLog("[AISession] Display error: %@", error.localizedDescription)
        }
    }

    /// Format and display a tool result on the glasses HUD.
    func displayToolResult(task: String, result: String) async {
        guard glassesProvider.displayCapability != .none else { return }

        let formatted = HUDFormatter.formatToolResult(
            toolName: "execute",
            task: task,
            result: result,
            maxChars: displayMaxChars
        )
        let style = DisplayStyle(title: "Done", priority: .normal)

        do {
            try await glassesProvider.displayText(formatted, style: style)
        } catch {
            NSLog("[AISession] Display error: %@", error.localizedDescription)
        }
    }
}
