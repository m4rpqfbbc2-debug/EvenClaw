// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// GestureController.swift
// Maps G2 BLE gesture events to app state transitions.
// This is the bridge between raw G2 events and the AppStateMachine.
//
// G2 Event Map:
//   Event 0 = single tap
//   Event 1 = slide forward (scroll up) on right arm
//   Event 2 = slide back (scroll down) on right arm
//   Event 3 = double-tap

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Gesture")

final class GestureController {

    // MARK: - Gesture Debounce

    private var lastGestureTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.3  // 300ms debounce

    // MARK: - Public

    /// Convert raw G2 event type to GlassesGesture.
    /// Returns nil if the event should be ignored (debounce / unknown).
    func processRawEvent(_ eventType: Int) -> GlassesGesture? {
        let now = Date()
        guard now.timeIntervalSince(lastGestureTime) >= debounceInterval else {
            log.debug("Gesture debounced (event \(eventType))")
            return nil
        }
        lastGestureTime = now

        switch eventType {
        case 0:
            log.info("Single tap")
            return .tap
        case 1:
            log.info("Slide forward")
            return .swipeForward
        case 2:
            log.info("Slide back")
            return .swipeBackward
        case 3:
            log.info("Double-tap")
            return .doubleTap
        default:
            log.debug("Unknown event type: \(eventType)")
            return nil
        }
    }

    /// Human-readable description of what a gesture does in the given state.
    static func gestureHint(for state: AppState) -> String {
        switch state {
        case .idle:
            return "SLIDE FORWARD → Start recording"
        case .listening:
            return "DOUBLE TAP → Send recording"
        case .processing:
            return "Processing..."
        case .response:
            return "SLIDE FWD → Record next  |  TAP → Continue  |  SLIDE BACK → History"
        case .conversationReady:
            return "SLIDE FWD → Record  |  TAP → End conversation"
        }
    }
}
