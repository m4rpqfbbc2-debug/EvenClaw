// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// GlassesProvider.swift
//
// Hardware abstraction protocol for smart glasses. Any glasses hardware
// (Even G2, Meta Ray-Ban, or future devices) implements this protocol
// to integrate with the EvenClaw AI pipeline.
//
// The protocol captures four capability axes:
//   - Display: what can be shown on the glasses HUD
//   - Audio: mic/speaker routing through glasses vs phone
//   - Camera: whether glasses have a camera or we use iPhone
//   - Input: touch/gesture controls available on the glasses
//

import UIKit

// MARK: - Capability Enums

/// Describes what the glasses can display.
enum DisplayCapability: Equatable {
    /// No display (e.g. phone-only mode)
    case none
    /// Text-only display with character limit (e.g. via ANCS notifications)
    case textOnly(maxChars: Int)
    /// Rich text display with formatting support (e.g. via native SDK)
    case richText(maxChars: Int)
    /// Full pixel display (future devices)
    case fullDisplay(width: Int, height: Int)

    /// Maximum characters that can be displayed, or nil if not text-based.
    var maxChars: Int? {
        switch self {
        case .none: return nil
        case .textOnly(let max): return max
        case .richText(let max): return max
        case .fullDisplay: return nil
        }
    }
}

/// Describes audio routing capabilities.
enum AudioCapability: Equatable {
    /// Audio stays on iPhone (mic + speaker)
    case phoneOnly
    /// Glasses have speakers only (output)
    case glassesOutput
    /// Glasses have both mic and speakers (full duplex)
    case glassesBidirectional
}

/// Describes camera capabilities.
enum CameraCapability: Equatable {
    /// No glasses camera — use iPhone back camera
    case phoneOnly
    /// Glasses have a camera with given specs
    case glassesCamera(maxFPS: Int, maxResolution: CGSize)
}

/// Describes input/gesture capabilities.
enum InputCapability: Equatable {
    /// No input from glasses
    case none
    /// Temple touchpad (tap, swipe)
    case touchpad
    /// Touchpad plus physical buttons
    case touchpadAndButtons
}

// MARK: - State Enums

/// Connection state of the glasses.
enum GlassesConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Gesture events from the glasses touchpad/buttons.
enum GlassesGesture: Equatable {
    case tap
    case doubleTap
    case swipeForward
    case swipeBackward
    case longPress
}

// MARK: - Display Styling

/// Priority level for HUD content.
enum DisplayPriority: Int, Comparable {
    case low = 0       // Informational, can be overwritten
    case normal = 1    // Standard AI response
    case high = 2      // Urgent notification

    static func < (lhs: DisplayPriority, rhs: DisplayPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Style configuration for displaying text on the HUD.
struct DisplayStyle {
    /// Optional title line (shown above body on some displays)
    var title: String?
    /// Auto-dismiss after this duration (nil = stay until replaced)
    var duration: TimeInterval?
    /// Priority level
    var priority: DisplayPriority

    /// Convenience initializer with sensible defaults.
    init(title: String? = nil, duration: TimeInterval? = nil, priority: DisplayPriority = .normal) {
        self.title = title
        self.duration = duration
        self.priority = priority
    }
}

// MARK: - GlassesProvider Protocol

/// Abstraction over any smart glasses hardware.
///
/// Implementations:
/// - `PhoneOnlyProvider` — no glasses, iPhone only
/// - `NotificationProvider` — any ANCS-compatible glasses (iOS notifications)
/// - `EvenG2Provider` — Even Realities G2 via future SDK
///
/// The AI pipeline (`AISessionManager`) uses this protocol to route
/// display output, audio, and camera input without knowing the hardware.
protocol GlassesProvider: AnyObject {

    // MARK: Capabilities (read-only, set at init)

    var displayCapability: DisplayCapability { get }
    var audioCapability: AudioCapability { get }
    var cameraCapability: CameraCapability { get }
    var inputCapability: InputCapability { get }

    // MARK: Connection

    var connectionState: GlassesConnectionState { get }
    var onConnectionStateChanged: ((GlassesConnectionState) -> Void)? { get set }

    func connect() async throws
    func disconnect()

    // MARK: Display

    /// Send text to the glasses HUD.
    func displayText(_ text: String, style: DisplayStyle) async throws

    /// Clear the glasses HUD.
    func clearDisplay() async throws

    // MARK: Input

    /// Callback for gesture events from the glasses.
    var onGesture: ((GlassesGesture) -> Void)? { get set }
}
