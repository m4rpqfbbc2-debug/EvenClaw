// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// EvenG2Provider.swift
//
// Stub GlassesProvider for Even Realities G2 smart glasses.
// This will be the full-featured provider once we have the Even Hub SDK.
//
// Current status: All methods throw — SDK not yet integrated.
//
// What the Even Hub SDK would provide:
// - BLE connection management (pairing, auto-reconnect)
// - Display API (send formatted text to the binocular micro-LED HUD)
// - Touch events (tap, swipe from temple touchpad)
// - Audio routing (route mic/speaker through glasses via Bluetooth Classic)
// - Notification integration (push custom content to HUD)
//
// BLE Discovery Notes:
// - G2 advertises over Bluetooth 5.3 (BLE)
// - Service UUIDs are not yet documented publicly
// - MentraOS (github.com/Mentra-Community/MentraOS) has G1 protocol reference
// - even-utils (github.com/radioegor146/even-utils) has partial G1 BLE docs
//

import Foundation
import CoreBluetooth

// MARK: - SDK Integration Error

enum EvenG2Error: LocalizedError {
    case sdkNotIntegrated
    case notConnected
    case bleUnavailable

    var errorDescription: String? {
        switch self {
        case .sdkNotIntegrated:
            return "Even Hub SDK not yet integrated. Use NotificationProvider for ANCS-based display."
        case .notConnected:
            return "Even G2 glasses not connected."
        case .bleUnavailable:
            return "Bluetooth LE is not available on this device."
        }
    }
}

// MARK: - EvenG2Provider

class EvenG2Provider: NSObject, GlassesProvider {

    // MARK: - Capabilities

    /// G2 has a binocular micro-LED HUD — rich text via SDK, ~200 chars usable
    let displayCapability: DisplayCapability = .richText(maxChars: 200)

    /// G2 has mic + speakers in temples, routed via Bluetooth Classic
    let audioCapability: AudioCapability = .glassesBidirectional

    /// G2 has NO camera — always use iPhone
    let cameraCapability: CameraCapability = .phoneOnly

    /// G2 has a temple touchpad for tap/swipe gestures
    let inputCapability: InputCapability = .touchpad

    // MARK: - Connection State

    private(set) var connectionState: GlassesConnectionState = .disconnected

    var onConnectionStateChanged: ((GlassesConnectionState) -> Void)?
    var onGesture: ((GlassesGesture) -> Void)?

    // MARK: - BLE Discovery (Stub)

    // TODO: Replace with Even Hub SDK connection manager when available.
    // For now, this provides a CoreBluetooth scanning stub that could be used
    // to discover G2 devices by their BLE advertisement.

    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?

    // TODO: Replace with actual Even G2 service UUIDs from SDK documentation
    // These are placeholder UUIDs — the real ones are not publicly documented.
    // Check MentraOS source for G1 UUIDs as reference:
    // github.com/Mentra-Community/MentraOS
    private let evenServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // Placeholder

    // MARK: - GlassesProvider

    /// Attempt to connect to Even G2 glasses via BLE.
    /// Currently throws — SDK not yet integrated.
    func connect() async throws {
        // TODO: When Even Hub SDK is available:
        // 1. Initialize SDK: EvenHub.configure()
        // 2. Scan for nearby G2 devices
        // 3. Pair and establish connection
        // 4. Set up display, audio, and touch event channels
        // 5. Update connectionState to .connected

        // For now, start BLE scanning as a proof-of-concept
        connectionState = .connecting
        onConnectionStateChanged?(.connecting)

        NSLog("[EvenG2] SDK not integrated — starting BLE discovery stub")
        centralManager = CBCentralManager(delegate: self, queue: nil)

        // The actual connection would happen in the CBCentralManagerDelegate callbacks
        // For now, we throw after a brief delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        connectionState = .error("SDK not yet integrated")
        onConnectionStateChanged?(.error("SDK not yet integrated"))
        throw EvenG2Error.sdkNotIntegrated
    }

    func disconnect() {
        // TODO: When SDK is available:
        // 1. Disconnect BLE
        // 2. Release audio routing
        // 3. Clean up SDK resources

        if let peripheral = discoveredPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager = nil
        discoveredPeripheral = nil
        connectionState = .disconnected
        onConnectionStateChanged?(.disconnected)
        NSLog("[EvenG2] Disconnected")
    }

    /// Display text on the G2 HUD.
    /// Currently throws — SDK not yet integrated.
    func displayText(_ text: String, style: DisplayStyle) async throws {
        // TODO: When SDK is available:
        // 1. Format text for G2 display (font size, position, duration)
        // 2. Send via SDK display API
        // 3. Handle priority (high = interrupt current display)
        // 4. Support auto-dismiss via style.duration

        guard connectionState == .connected else {
            throw EvenG2Error.notConnected
        }
        throw EvenG2Error.sdkNotIntegrated
    }

    /// Clear the G2 HUD.
    /// Currently throws — SDK not yet integrated.
    func clearDisplay() async throws {
        // TODO: When SDK is available:
        // 1. Send clear command via SDK
        // 2. Return to default HUD state (time, battery, etc.)

        guard connectionState == .connected else {
            throw EvenG2Error.notConnected
        }
        throw EvenG2Error.sdkNotIntegrated
    }
}

// MARK: - CoreBluetooth Delegate (BLE Discovery Stub)

extension EvenG2Provider: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            NSLog("[EvenG2] BLE powered on — scanning for G2 devices...")
            // TODO: Use actual Even G2 service UUIDs when known
            central.scanForPeripherals(
                withServices: nil, // Scan for all — filter by name until we know UUIDs
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .poweredOff:
            NSLog("[EvenG2] BLE powered off")
            connectionState = .error("Bluetooth is off")
            onConnectionStateChanged?(.error("Bluetooth is off"))
        case .unauthorized:
            NSLog("[EvenG2] BLE unauthorized")
            connectionState = .error("Bluetooth permission denied")
            onConnectionStateChanged?(.error("Bluetooth permission denied"))
        default:
            NSLog("[EvenG2] BLE state: %d", central.state.rawValue)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Look for devices with "Even" or "G2" in the name
        // TODO: Replace with proper service UUID filtering when SDK docs are available
        guard let name = peripheral.name,
              (name.lowercased().contains("even") || name.lowercased().contains("g2")) else {
            return
        }

        NSLog("[EvenG2] Discovered potential G2: %@ (RSSI: %@)", name, RSSI)
        discoveredPeripheral = peripheral
        central.stopScan()

        // TODO: With SDK — connect and begin pairing flow
        // central.connect(peripheral, options: nil)
    }
}
