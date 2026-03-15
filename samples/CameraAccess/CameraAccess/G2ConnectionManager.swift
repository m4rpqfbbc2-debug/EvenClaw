// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2ConnectionManager.swift
// BLE lifecycle: scan, connect, authenticate, disconnect, auto-reconnect.

import Foundation
import CoreBluetooth
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Connection")

enum G2Error: LocalizedError {
    case deviceNotFound
    case notConnected
    case connectionFailed(String)
    case authFailed(String)
    case bleNotReady

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "G2 glasses not found"
        case .notConnected: return "Not connected to glasses"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authFailed(let msg): return "Auth failed: \(msg)"
        case .bleNotReady: return "Bluetooth not available"
        }
    }
}

protocol G2ConnectionDelegate: AnyObject {
    @MainActor func connectionDidChange(connected: Bool, authenticated: Bool)
    @MainActor func connectionDidReceivePacket(direction: String, data: Data)
    @MainActor func connectionDidFail(error: G2Error)
    @MainActor func connectionDidDiscover(writeChar: CBCharacteristic, notifyChar: CBCharacteristic, peripheral: CBPeripheral)
}

@MainActor
class G2ConnectionManager: NSObject {

    weak var delegate: G2ConnectionDelegate?

    private(set) var centralManager: CBCentralManager!
    private(set) var peripheral: CBPeripheral?
    private(set) var writeChar: CBCharacteristic?
    private(set) var notifyChar: CBCharacteristic?
    private(set) var isConnected = false
    private(set) var isAuthenticated = false

    private var connectContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Auto-Reconnect

    private var shouldAutoReconnect = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 2.0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func connectAndAuth() async throws {
        shouldAutoReconnect = true
        reconnectAttempt = 0

        if centralManager.state != .poweredOn {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        guard centralManager.state == .poweredOn else {
            throw G2Error.bleNotReady
        }

        try await findAndConnect()
        try await performAuth()
        isAuthenticated = true
        delegate?.connectionDidChange(connected: true, authenticated: true)
    }

    func disconnect() {
        shouldAutoReconnect = false
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        cleanup()
        delegate?.connectionDidChange(connected: false, authenticated: false)
    }

    // MARK: - Auto-Reconnect Logic

    private func attemptReconnect() {
        guard shouldAutoReconnect, reconnectAttempt < maxReconnectAttempts else {
            log.warning("Auto-reconnect exhausted (\(self.reconnectAttempt)/\(self.maxReconnectAttempts))")
            delegate?.connectionDidFail(error: .connectionFailed("Auto-reconnect failed after \(reconnectAttempt) attempts"))
            return
        }

        reconnectAttempt += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1))
        log.info("Auto-reconnect attempt \(self.reconnectAttempt) in \(delay)s...")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            do {
                try await connectAndAuth()
                log.info("Auto-reconnect succeeded on attempt \(self.reconnectAttempt)")
                reconnectAttempt = 0
            } catch {
                log.error("Auto-reconnect attempt \(self.reconnectAttempt) failed: \(error.localizedDescription)")
                attemptReconnect()
            }
        }
    }

    // MARK: - Find & Connect

    private func findAndConnect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectContinuation = cont

            let serviceUUIDs: [CBUUID] = [
                G2Constants.serviceUUID,
                CBUUID(string: "180A"),
                CBUUID(string: "180F"),
                CBUUID(string: "1800"),
                CBUUID(string: "1801"),
            ]
            for svc in serviceUUIDs {
                let connected = self.centralManager.retrieveConnectedPeripherals(withServices: [svc])
                for p in connected {
                    if let name = p.name, G2Constants.isG2Device(name: name) {
                        log.info("Found paired G2: \(name)")
                        self.peripheral = p
                        p.delegate = self
                        self.centralManager.connect(p, options: nil)
                        return
                    }
                }
            }

            self.centralManager.scanForPeripherals(withServices: nil, options: nil)

            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if self.peripheral == nil {
                    self.centralManager.stopScan()
                    self.connectContinuation?.resume(throwing: G2Error.deviceNotFound)
                    self.connectContinuation = nil
                }
            }
        }
    }

    // MARK: - Auth

    private func performAuth() async throws {
        guard let writeChar, let peripheral else { throw G2Error.notConnected }

        let authPackets = G2PacketBuilder.buildAuthSequence()
        for (i, pkt) in authPackets.enumerated() {
            peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
            delegate?.connectionDidReceivePacket(direction: "TX", data: pkt)
            log.debug("Auth \(i+1)/7 sent")
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - Write

    func writeValue(_ data: Data) {
        guard let writeChar, let peripheral else { return }
        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }

    // MARK: - Cleanup

    private func cleanup() {
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
        isAuthenticated = false
    }
}

// MARK: - CBCentralManagerDelegate

extension G2ConnectionManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            log.info("BLE state: \(central.state.rawValue)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, G2Constants.isG2Device(name: name) else { return }
        Task { @MainActor in
            log.info("Found G2: \(name)")
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            log.info("Connected to \(peripheral.name ?? "?")")
            self.isConnected = true
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let msg = error?.localizedDescription ?? "unknown"
            self.connectContinuation?.resume(throwing: G2Error.connectionFailed(msg))
            self.connectContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.cleanup()
            self.delegate?.connectionDidChange(connected: false, authenticated: false)
            // Auto-reconnect on unexpected disconnection
            if self.shouldAutoReconnect {
                log.info("Unexpected disconnection — attempting auto-reconnect")
                self.attemptReconnect()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension G2ConnectionManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        Task { @MainActor in
            for service in services {
                log.info("Service: \(service.uuid)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        Task { @MainActor in
            for char in chars {
                log.info("  Char: \(char.uuid) props=\(char.properties.rawValue)")

                if char.uuid == G2Constants.charWrite {
                    self.writeChar = char
                }
                if char.uuid == G2Constants.charNotify {
                    self.notifyChar = char
                    peripheral.setNotifyValue(true, for: char)
                }
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }

            if let w = self.writeChar, let n = self.notifyChar {
                self.isConnected = true
                self.delegate?.connectionDidDiscover(writeChar: w, notifyChar: n, peripheral: peripheral)
                self.connectContinuation?.resume()
                self.connectContinuation = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.delegate?.connectionDidReceivePacket(direction: "RX", data: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                log.error("Notify failed for \(characteristic.uuid): \(error.localizedDescription)")
            } else {
                log.info("Notify ON for \(characteristic.uuid)")
            }
        }
    }
}
