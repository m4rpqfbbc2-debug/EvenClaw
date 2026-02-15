// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2BLEManager.swift
// CoreBluetooth manager for Even G2 glasses. Handles scanning, connecting,
// the 7-packet auth handshake, and sending/receiving packets.

import Foundation
import CoreBluetooth
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "G2BLE")

/// Delegate for G2 BLE events.
protocol G2BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: G2BLEManager, didChangeState state: G2BLEManager.State)
    func bleManager(_ manager: G2BLEManager, didReceiveData data: Data)
    func bleManager(_ manager: G2BLEManager, didDiscoverDevice name: String, rssi: NSNumber)
}

class G2BLEManager: NSObject {

    enum State: Equatable {
        case idle
        case scanning
        case connecting
        case authenticating
        case connected
        case disconnected
        case error(String)
    }

    // MARK: - Properties

    weak var delegate: G2BLEManagerDelegate?

    private(set) var state: State = .idle {
        didSet {
            if state != oldValue {
                delegate?.bleManager(self, didChangeState: state)
            }
        }
    }

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var displayCharacteristic: CBCharacteristic?

    private var sequenceCounter: UInt8 = 0x08  // Start after auth (0x01-0x07)
    private var msgIDCounter: Int = 0x14       // Start after auth msg IDs

    /// Continuations for async connect/auth flow
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var scanTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "g2ble"))
    }

    // MARK: - Public API

    /// Scan, connect, authenticate. Returns when fully connected or throws on failure.
    func connectToGlasses() async throws {
        if centralManager.state != .poweredOn {
            // Wait for BLE to power on
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard centralManager.state == .poweredOn else {
                state = .error("Bluetooth is not available")
                throw G2Error.bleUnavailable
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.state = .scanning
            log.info("Scanning for Even G2 glasses...")
            self.centralManager.scanForPeripherals(
                withServices: nil, // Scan all — filter by name
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        // Start scan timeout
        scanTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
            if case .scanning = self.state {
                self.centralManager.stopScan()
                self.state = .error("No G2 glasses found")
                self.connectContinuation?.resume(throwing: G2Error.deviceNotFound)
                self.connectContinuation = nil
            }
        }
    }

    func disconnect() {
        scanTimeoutTask?.cancel()
        centralManager.stopScan()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        displayCharacteristic = nil
        sequenceCounter = 0x08
        msgIDCounter = 0x14
        state = .disconnected
        log.info("Disconnected")
    }

    /// Send a pre-built packet to the write characteristic (0x5401).
    func sendPacket(_ data: Data) {
        guard let char = writeCharacteristic, let p = peripheral else {
            log.warning("Cannot send — not connected")
            return
        }
        p.writeValue(data, for: char, type: .withoutResponse)
    }

    /// Send data to the display rendering characteristic (0x6402).
    func sendDisplayData(_ data: Data) {
        guard let char = displayCharacteristic, let p = peripheral else { return }
        p.writeValue(data, for: char, type: .withoutResponse)
    }

    /// Get next sequence number (wraps 0-255).
    func nextSeq() -> UInt8 {
        let seq = sequenceCounter
        sequenceCounter = sequenceCounter &+ 1
        return seq
    }

    /// Get next message ID.
    func nextMsgID() -> Int {
        let id = msgIDCounter
        msgIDCounter += 1
        return id
    }

    // MARK: - Authentication

    private func performAuth() async throws {
        state = .authenticating
        log.info("Starting 7-packet auth handshake...")

        let authPackets = G2PacketBuilder.buildAuthSequence()
        for (i, pkt) in authPackets.enumerated() {
            sendPacket(pkt)
            log.debug("Auth packet \(i + 1)/7 sent (\(pkt.count) bytes)")
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms between packets
        }

        // Wait for auth to settle
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        state = .connected
        log.info("Auth complete — connected")
    }
}

// MARK: - CBCentralManagerDelegate

extension G2BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("BLE state: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            break // Ready
        case .poweredOff:
            state = .error("Bluetooth is off")
        case .unauthorized:
            state = .error("Bluetooth permission denied")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, G2Constants.isG2Device(name: name) else { return }

        // Prefer left ear (primary connection)
        if !G2Constants.isLeftEar(name: name), self.peripheral == nil {
            // Accept right ear if no left found yet, but keep scanning briefly
            log.info("Found right ear: \(name) (RSSI: \(RSSI))")
            delegate?.bleManager(self, didDiscoverDevice: name, rssi: RSSI)
            return
        }

        log.info("Found G2: \(name) (RSSI: \(RSSI))")
        delegate?.bleManager(self, didDiscoverDevice: name, rssi: RSSI)

        central.stopScan()
        scanTimeoutTask?.cancel()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("Connected to \(peripheral.name ?? "unknown")")
        peripheral.discoverServices([G2Constants.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "Unknown error"
        log.error("Connection failed: \(msg)")
        state = .error(msg)
        connectContinuation?.resume(throwing: G2Error.connectionFailed(msg))
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Disconnected: \(error?.localizedDescription ?? "clean")")
        self.peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        displayCharacteristic = nil
        state = .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension G2BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            log.debug("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics([
                G2Constants.charWrite,
                G2Constants.charNotify,
                G2Constants.charDisplay
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }

        for char in chars {
            log.debug("Characteristic: \(char.uuid) props=\(char.properties.rawValue)")

            if char.uuid == G2Constants.charWrite {
                writeCharacteristic = char
            } else if char.uuid == G2Constants.charNotify {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            } else if char.uuid == G2Constants.charDisplay {
                displayCharacteristic = char
            }
        }

        // If we have write + notify, start auth
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            Task {
                do {
                    try await performAuth()
                    connectContinuation?.resume()
                    connectContinuation = nil
                } catch {
                    connectContinuation?.resume(throwing: error)
                    connectContinuation = nil
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        delegate?.bleManager(self, didReceiveData: data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log.error("Notify enable failed: \(error.localizedDescription)")
        } else {
            log.info("Notifications enabled for \(characteristic.uuid)")
        }
    }
}

// MARK: - Errors

enum G2Error: LocalizedError {
    case bleUnavailable
    case deviceNotFound
    case connectionFailed(String)
    case notConnected
    case authFailed

    var errorDescription: String? {
        switch self {
        case .bleUnavailable: return "Bluetooth LE is not available"
        case .deviceNotFound: return "No Even G2 glasses found nearby"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .notConnected: return "Even G2 glasses not connected"
        case .authFailed: return "Authentication handshake failed"
        }
    }
}
