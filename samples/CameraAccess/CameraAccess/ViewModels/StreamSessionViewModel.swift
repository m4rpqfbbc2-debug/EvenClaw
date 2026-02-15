// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// StreamSessionViewModel.swift
//
// LEGACY FILE — Simplified for EvenClaw (Meta DAT SDK removed).
// EvenClaw only uses iPhone camera mode. The glasses streaming code
// from VisionClaw has been removed since Even G2 has no camera.
//
// For the full AI pipeline, use AISessionManager instead.
// This file is kept for backward compatibility with existing views.
//

import SwiftUI

// Meta DAT SDK imports — removed for EvenClaw
// import MWDATCamera
// import MWDATCore

enum StreamingStatus {
    case streaming
    case waiting
    case stopped
}

enum StreamingMode {
    case glasses
    case iPhone
}

@MainActor
class StreamSessionViewModel: ObservableObject {
    @Published var currentVideoFrame: UIImage?
    @Published var hasReceivedFirstFrame: Bool = false
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var hasActiveDevice: Bool = false
    @Published var streamingMode: StreamingMode = .iPhone  // Always iPhone for EvenClaw

    var isStreaming: Bool {
        streamingStatus != .stopped
    }

    // Photo capture properties
    @Published var capturedPhoto: UIImage?
    @Published var showPhotoPreview: Bool = false

    // Gemini Live integration
    var geminiSessionVM: GeminiSessionViewModel?

    // WebRTC Live streaming integration
    var webrtcSessionVM: WebRTCSessionViewModel?

    private var iPhoneCameraManager: IPhoneCameraManager?

    init() {
        // EvenClaw: no DAT SDK initialization needed
    }

    // MARK: - iPhone Camera Mode (Primary for EvenClaw)

    func handleStartIPhone() async {
        let granted = await IPhoneCameraManager.requestPermission()
        if granted {
            startIPhoneSession()
        } else {
            showError("Camera permission denied. Please grant access in Settings.")
        }
    }

    private func startIPhoneSession() {
        streamingMode = .iPhone
        let camera = IPhoneCameraManager()
        camera.onFrameCaptured = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentVideoFrame = image
                if !self.hasReceivedFirstFrame {
                    self.hasReceivedFirstFrame = true
                }
                self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
                self.webrtcSessionVM?.pushVideoFrame(image)
            }
        }
        camera.start()
        iPhoneCameraManager = camera
        streamingStatus = .streaming
        NSLog("[Stream] iPhone camera mode started")
    }

    func stopSession() async {
        stopIPhoneSession()
    }

    private func stopIPhoneSession() {
        iPhoneCameraManager?.stop()
        iPhoneCameraManager = nil
        currentVideoFrame = nil
        hasReceivedFirstFrame = false
        streamingStatus = .stopped
        NSLog("[Stream] iPhone camera mode stopped")
    }

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    func dismissPhotoPreview() {
        showPhotoPreview = false
        capturedPhoto = nil
    }
}
