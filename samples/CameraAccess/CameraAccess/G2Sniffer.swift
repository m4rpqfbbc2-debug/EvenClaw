// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2Sniffer.swift
// Connects to Even G2, does auth, logs ALL BLE packets.
// Primary goal: capture Conversate (0x0B-20) handshake when "Hey Even" triggers.

import Foundation
import CoreBluetooth
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Sniffer")

// MARK: - Packet Log Entry

struct PacketLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let direction: String  // "RX" or "TX"
    let serviceHi: UInt8
    let serviceLo: UInt8
    let rawData: Data
    let parsedContent: String?

    var serviceLabel: String {
        let svc = String(format: "%02X-%02X", serviceHi, serviceLo)
        switch (serviceHi, serviceLo) {
        case (0x80, 0x00): return "\(svc) Auth"
        case (0x80, 0x20): return "\(svc) AuthData"
        case (0x80, 0x01): return "\(svc) AuthResp"
        case (0x04, 0x20): return "\(svc) DispWake"
        case (0x06, 0x20): return "\(svc) Teleprmp"
        case (0x07, 0x20): return "\(svc) Dashbrd"
        case (0x09, 0x00): return "\(svc) DevInfo"
        case (0x09, 0x20): return "\(svc) Touch"
        case (0x08, 0x20): return "\(svc) Touch2"
        case (0x0B, 0x20): return "\(svc) CONVRST"
        case (0x0C, 0x20): return "\(svc) Tasks"
        case (0x0D, 0x00): return "\(svc) Config"
        case (0x0E, 0x20): return "\(svc) DispCfg"
        case (0x11, 0x20): return "\(svc) ConvAlt"
        case (0x20, 0x20): return "\(svc) Commit"
        case (0x81, 0x20): return "\(svc) DispTrig"
        default: return svc
        }
    }

    var isConversate: Bool {
        (serviceHi == 0x0B && serviceLo == 0x20) || (serviceHi == 0x11 && serviceLo == 0x20)
    }

    var hexDump: String {
        rawData.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var size: Int { rawData.count }
}

// MARK: - G2 Sniffer

@MainActor
class G2Sniffer: NSObject, ObservableObject {

    @Published var bleConnected = false
    @Published var authenticated = false
    @Published var openClawConnected = false
    @Published var packetLog: [PacketLogEntry] = []
    @Published var packetCount = 0
    @Published var statusMessage = ""
    @Published var conversateText = ""
    @Published var conversateFinal = false

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func connectAndAuth() async {
        statusMessage = "Scanning for G2..."

        // Wait for BLE to be ready
        if centralManager.state != .poweredOn {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not available"
            return
        }

        do {
            try await findAndConnect()
            statusMessage = "Connected. Authenticating..."
            try await performAuth()
            authenticated = true
            statusMessage = "Ready. Say 'Hey Even' — watching for Conversate packets..."

            // Check OpenClaw too
            let bridge = OpenClawBridge()
            await bridge.checkConnection()
            openClawConnected = bridge.connectionState == .connected
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        bleConnected = false
        authenticated = false
        statusMessage = "Disconnected"
    }

    func clearLog() {
        packetLog.removeAll()
        packetCount = 0
        conversateText = ""
        conversateFinal = false
    }

    func exportLog() -> String {
        packetLog.map { entry in
            "\(entry.timestamp) \(entry.direction) \(entry.serviceLabel) (\(entry.size)B): \(entry.hexDump)" +
            (entry.parsedContent.map { " → \($0)" } ?? "")
        }.joined(separator: "\n")
    }

    // MARK: - Find & Connect

    private func findAndConnect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectContinuation = cont

            // Try retrieveConnectedPeripherals first (already paired in iOS Settings)
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
                        self.statusMessage = "Found \(name)"
                        self.peripheral = p
                        p.delegate = self
                        p.discoverServices(nil)
                        return
                    }
                }
            }

            // Fallback: scan
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)

            // Timeout after 15s
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
            logPacket(direction: "TX", data: pkt)
            log.debug("Auth \(i+1)/7 sent")
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - Packet Logging

    private func logPacket(direction: String, data: Data) {
        // Parse header
        var serviceHi: UInt8 = 0
        var serviceLo: UInt8 = 0
        if data.count >= 8 {
            serviceHi = data[6]
            serviceLo = data[7]
        }

        // Try to parse Conversate content
        var parsed: String? = nil
        if data.count >= 8 && serviceHi == 0x0B && serviceLo == 0x20 {
            // Strip header (8 bytes) and CRC (2 bytes) to get payload
            if data.count > 10 {
                let payload = data.subdata(in: 8..<(data.count - 2))
                if let result = ConversateParser.parseConversateMessage(payload) {
                    parsed = "💬 \"\(result.text)\" final=\(result.isFinal)"
                    conversateText = result.text
                    conversateFinal = result.isFinal
                    log.info("CONVERSATE: \"\(result.text)\" final=\(result.isFinal)")
                }
            }
        }

        // Also check alt conversate (0x11-20)
        if data.count >= 8 && serviceHi == 0x11 && serviceLo == 0x20 {
            if data.count > 10 {
                let payload = data.subdata(in: 8..<(data.count - 2))
                if let result = ConversateParser.parseConversateMessage(payload) {
                    parsed = "💬 ALT \"\(result.text)\" final=\(result.isFinal)"
                    conversateText = result.text
                    conversateFinal = result.isFinal
                }
            }
        }

        let entry = PacketLogEntry(
            timestamp: dateFormatter.string(from: Date()),
            direction: direction,
            serviceHi: serviceHi,
            serviceLo: serviceLo,
            rawData: data,
            parsedContent: parsed
        )

        packetLog.append(entry)
        packetCount += 1

        // Keep log manageable
        if packetLog.count > 500 {
            packetLog.removeFirst(100)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension G2Sniffer: CBCentralManagerDelegate {

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
            self.statusMessage = "Found \(name)"
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            log.info("Connected to \(peripheral.name ?? "?")")
            self.bleConnected = true
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.statusMessage = "Connection failed: \(error?.localizedDescription ?? "?")"
            self.connectContinuation?.resume(throwing: G2Error.connectionFailed(error?.localizedDescription ?? "unknown"))
            self.connectContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.bleConnected = false
            self.authenticated = false
            self.statusMessage = "Disconnected"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension G2Sniffer: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        Task { @MainActor in
            for service in services {
                log.info("Service: \(service.uuid)")
                peripheral.discoverCharacteristics(nil, for: service) // Discover ALL characteristics
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
                // Subscribe to ALL notify characteristics to catch everything
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }

            // Resume continuation once we have write + notify
            if self.writeChar != nil && self.notifyChar != nil {
                self.bleConnected = true
                self.connectContinuation?.resume()
                self.connectContinuation = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.logPacket(direction: "RX", data: data)
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
