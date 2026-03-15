// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClawController.swift
// Core orchestration: wires VoiceCommandManager ↔ G2Sniffer state,
// manages status updates, and coordinates HUD display callbacks.

import Foundation

@MainActor
class EvenClawController {

    // MARK: - Dependencies

    private weak var sniffer: G2Sniffer?
    private let voiceCommandManager: VoiceCommandManager
    private let g2BLEManager: G2BLEManager
    private var statusTimer: Timer?

    // MARK: - Init

    init(sniffer: G2Sniffer, voiceCommandManager: VoiceCommandManager, g2BLEManager: G2BLEManager) {
        self.sniffer = sniffer
        self.voiceCommandManager = voiceCommandManager
        self.g2BLEManager = g2BLEManager

        wireCallbacks()
        startStatusUpdateTimer()
    }

    deinit {
        statusTimer?.invalidate()
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        guard let sniffer else { return }

        // Wire HUD display through G2Sniffer (which has the actual BLE connection)
        voiceCommandManager.onHUDDisplay = { [weak sniffer] text in
            guard let sniffer else { return }
            if !sniffer.evenAIActive {
                await sniffer.enterEvenAIMode()
            }
            await sniffer.sendReply(text)
        }

        // Immediate state sync from VCM → sniffer
        voiceCommandManager.onStateChange = { [weak sniffer] newState in
            Task { @MainActor in
                guard let sniffer else { return }
                switch newState {
                case .listening:
                    sniffer.isListening = true
                    sniffer.isProcessing = false
                case .sending, .processing:
                    sniffer.isListening = false
                    sniffer.isProcessing = true
                case .idle, .waitingForTouchBar:
                    if !sniffer.snifferOwnRecording {
                        sniffer.isListening = false
                    }
                    sniffer.isProcessing = false
                case .error:
                    sniffer.isListening = false
                    sniffer.isProcessing = false
                case .recordingFromG2:
                    sniffer.isListening = true
                    sniffer.isProcessing = false
                }
            }
        }
    }

    // MARK: - Periodic Status Sync

    private func startStatusUpdateTimer() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncStatus()
            }
        }
    }

    private func syncStatus() {
        guard let sniffer else { return }
        let vcm = voiceCommandManager

        sniffer.wakeWordActive = vcm.wakeWordActive
        sniffer.headGestureActive = vcm.headGestureDetectorIsActive
        sniffer.headGestureSource = vcm.headGestureDetectorSource

        // Sync VCM listening state → sniffer for waveform UI
        if vcm.state == .listening {
            sniffer.isListening = true
            sniffer.audioLevelHistory = vcm.audioLevelHistory
        } else if !sniffer.snifferOwnRecording {
            if sniffer.isListening && vcm.state != .listening {
                sniffer.isListening = false
            }
        }

        // Sync processing state for Space Invaders animation
        switch vcm.state {
        case .sending, .processing:
            sniffer.isProcessing = true
        default:
            sniffer.isProcessing = false
        }

        updateMicStatus()
    }

    func updateMicStatus() {
        guard let sniffer else { return }
        let vcm = voiceCommandManager

        switch vcm.state {
        case .listening:
            sniffer.micStatus = "🎙️ Aisha listening..."
        case .processing, .sending:
            sniffer.micStatus = "⏳ Thinking..."
        case .idle:
            if sniffer.wakeWordActive && sniffer.headGestureActive {
                sniffer.micStatus = "🔵 'Hey Aisha' or look up (\(sniffer.headGestureSource))"
            } else if sniffer.wakeWordActive {
                sniffer.micStatus = "🔵 Listening for 'Hey Aisha'..."
            } else if sniffer.headGestureActive {
                sniffer.micStatus = "🔵 Look up to talk (\(sniffer.headGestureSource))"
            } else {
                sniffer.micStatus = "Waiting for TouchBar..."
            }
        case .error(let msg):
            sniffer.micStatus = "❌ \(msg)"
        default:
            sniffer.micStatus = "Waiting..."
        }
    }
}
