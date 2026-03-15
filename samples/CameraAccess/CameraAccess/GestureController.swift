// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// GestureController.swift
// Maps G2 touch events to app state machine actions.
// Replaces WakeWordDetector as primary input method.
//
// G2 touch events (right arm):
//   Event 0 = single tap
//   Event 1 = slide forward (scroll up)
//   Event 2 = slide back (scroll down)
//   Event 3 = double-tap
//   Events 4/5 = app lifecycle (ignored)

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Gesture")

@MainActor
class GestureController: ObservableObject {

    // MARK: - State Machine Reference

    weak var stateMachine: AppStateMachine?

    // MARK: - Event Constants

    enum G2Event: Int {
        case singleTap = 0
        case slideForward = 1    // scroll up / activate
        case slideBack = 2       // scroll down / history
        case doubleTap = 3
        case appResume = 4       // lifecycle, ignore
        case appSuspend = 5      // lifecycle, ignore
    }

    // MARK: - Handle Raw G2 Touch Event

    /// Called when a touch event is received from G2 BLE.
    /// Maps the event to the appropriate action based on current app state.
    func handleEvent(_ eventType: Int) {
        guard let sm = stateMachine else {
            log.warning("GestureController has no state machine reference")
            return
        }

        guard let event = G2Event(rawValue: eventType) else {
            log.debug("Unknown event type: \(eventType)")
            return
        }

        let currentState = sm.state
        log.info("Event: \(eventType) (\(String(describing: event))) state: \(currentState.rawValue)")

        switch event {

        // ── SLIDE FORWARD (1) — primary activation gesture ──
        case .slideForward:
            switch currentState {
            case .idle:
                // Start new conversation
                log.info("Slide forward — starting conversation")
                sm.startListening()

            case .conversationReady:
                // Record next message in conversation
                log.info("Slide forward — recording next message")
                sm.startListening()

            case .response:
                // Dismiss response and start recording next message
                log.info("Slide forward — dismiss response, start recording")
                sm.startListening()

            case .listening, .processing:
                // Already active, ignore
                break
            }

        // ── SLIDE BACK (2) — scroll through response history ──
        case .slideBack:
            if currentState == .response {
                sm.scrollBack()
            }

        // ── DOUBLE TAP (3) — send recording / dismiss response ──
        case .doubleTap:
            switch currentState {
            case .listening:
                // Force send the recording
                log.info("Double-tap — sending recording now")
                sm.sendRecording()

            case .response:
                // Dismiss response, stay in conversation
                log.info("Double-tap — dismissing, ready for next message")
                sm.goConversationReady()

            case .conversationReady:
                // Also start recording
                log.info("Double-tap — recording next message")
                sm.startListening()

            case .idle, .processing:
                break
            }

        // ── SINGLE TAP (0) — dismiss / end ──
        case .singleTap:
            switch currentState {
            case .response:
                // Dismiss response, stay in conversation
                log.info("Tap — dismissing, ready for next message")
                sm.goConversationReady()

            case .conversationReady:
                // End conversation, back to idle
                log.info("Tap — ending conversation, back to idle")
                sm.goIdle()

            case .idle, .listening, .processing:
                break
            }

        // ── APP LIFECYCLE (4/5) — ignore ──
        case .appResume, .appSuspend:
            break
        }
    }

    // MARK: - Map GlassesGesture to Event

    /// Convenience: map GlassesGesture enum to G2 event number.
    func handleGlassesGesture(_ gesture: GlassesGesture) {
        switch gesture {
        case .tap:
            handleEvent(G2Event.singleTap.rawValue)
        case .swipeForward:
            handleEvent(G2Event.slideForward.rawValue)
        case .swipeBackward:
            handleEvent(G2Event.slideBack.rawValue)
        case .doubleTap:
            handleEvent(G2Event.doubleTap.rawValue)
        case .longPress:
            // Treat long press same as slide forward (activate)
            handleEvent(G2Event.slideForward.rawValue)
        }
    }

    // MARK: - Map TouchBar Events to Gestures

    /// Maps legacy 0xF5 TouchBar events to gesture events.
    /// TouchBar 0x17 (start) + 0x18 (stop) within short window = tap.
    /// Long hold 0x17 = slide forward (activate).
    private var touchBarStartTime: Date?
    private var lastTapTime: Date?
    private let maxTapDuration: TimeInterval = 0.4
    private let doubleTapWindow: TimeInterval = 0.6

    func handleTouchBarEvent(_ subcmd: UInt8) {
        switch subcmd {
        case G2Constants.TouchBar.evenAIStart:
            // TouchBar pressed
            touchBarStartTime = Date()

        case G2Constants.TouchBar.evenAIStop:
            // TouchBar released
            guard let startTime = touchBarStartTime else { return }
            let holdDuration = Date().timeIntervalSince(startTime)
            touchBarStartTime = nil

            if holdDuration <= maxTapDuration {
                // Quick tap — check for double-tap
                let now = Date()
                if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) <= doubleTapWindow {
                    // Double tap
                    lastTapTime = nil
                    handleEvent(G2Event.doubleTap.rawValue)
                } else {
                    lastTapTime = now
                    // Wait briefly to see if double-tap follows
                    DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow + 0.05) { [weak self] in
                        guard let self else { return }
                        // If lastTapTime is still set, it was a single tap
                        if self.lastTapTime != nil {
                            self.lastTapTime = nil
                            self.handleEvent(G2Event.singleTap.rawValue)
                        }
                    }
                }
            } else {
                // Long hold = activate (slide forward equivalent)
                handleEvent(G2Event.slideForward.rawValue)
            }

        default:
            break
        }
    }
}
