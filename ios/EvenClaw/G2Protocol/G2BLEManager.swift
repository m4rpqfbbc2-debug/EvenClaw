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
    func bleManager(_ manager: G2BLEManager, didReceiveVoiceTranscript text: String, isFinal: Bool)
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

    /// Creates a G2BLEManager that owns its own CBCentralManager (standalone mode).
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "g2ble"))
    }

    /// Creates a G2BLEManager that reuses an external CBCentralManager.
    /// The caller is responsible for keeping the central manager alive and
    /// must NOT set its delegate elsewhere after this call.
    init(centralManager: CBCentralManager) {
        super.init()
        self.centralManager = centralManager
    }

    // MARK: - Public API

    /// Connect to a pre-discovered, already-connected peripheral.
    /// Skips scanning entirely — discovers services, finds G2 characteristics,
    /// subscribes to notifications, and runs the 7-packet auth handshake.
    func connectToKnownPeripheral(_ peripheral: CBPeripheral) async throws {
        log.info("Connecting to known peripheral: '\(peripheral.name ?? "?")'")
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting

        // Discover all services on this peripheral
        peripheral.discoverServices(nil)

        // Wait for characteristic discovery + auth to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
        }
    }

    /// Connect using a pre-discovered peripheral via the central manager (needs explicit connect call).
    func connectToPeripheral(_ peripheral: CBPeripheral) async throws {
        log.info("Connecting to pre-found peripheral: '\(peripheral.name ?? "?")'")
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    func connectToGlasses() async throws {
        // Wait up to 5 seconds for BLE to power on
        var waitAttempts = 0
        while centralManager.state != .poweredOn && waitAttempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitAttempts += 1
        }
        log.info("BLE state after wait: \(self.centralManager.state.rawValue) (waited \(waitAttempts * 100)ms)")
        guard centralManager.state == .poweredOn else {
            let stateDesc: String
            switch centralManager.state {
            case .unauthorized: stateDesc = "Bluetooth permission denied — check Settings"
            case .poweredOff: stateDesc = "Bluetooth is turned off"
            case .unsupported: stateDesc = "This device doesn't support BLE"
            default: stateDesc = "Bluetooth unavailable (state: \(self.centralManager.state.rawValue))"
            }
            state = .error(stateDesc)
            log.error("BLE not available: \(stateDesc)")
            throw G2Error.bleUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            self.state = .scanning
            
            // First: check for already-connected G2 peripherals (paired via iOS Settings)
            // Try multiple service UUIDs — iOS may not know about the custom G2 service
            // until after explicit service discovery
            let commonBLEServices: [CBUUID] = [
                G2Constants.serviceUUID,                    // Custom G2 service
                CBUUID(string: "180A"),                     // Device Information
                CBUUID(string: "180F"),                     // Battery Service
                CBUUID(string: "1800"),                     // Generic Access
                CBUUID(string: "1801"),                     // Generic Attribute
            ]
            var foundConnected = false
            for svcUUID in commonBLEServices {
                let connected = self.centralManager.retrieveConnectedPeripherals(withServices: [svcUUID])
                for p in connected {
                    let pName = p.name ?? "G2"
                    log.info("Found connected peripheral via \(svcUUID): '\(pName)'")
                    // Accept any peripheral found via G2 service UUID, or matching name
                    if svcUUID == G2Constants.serviceUUID || G2Constants.isG2Device(name: pName) || pName.lowercased().contains("pair") || pName.lowercased().contains("even") {
                        self.delegate?.bleManager(self, didDiscoverDevice: pName, rssi: NSNumber(value: 0))
                        if self.peripheral == nil {
                            self.peripheral = p
                            p.delegate = self
                            self.state = .connecting
                            // Discover ALL services — not just our custom one
                            p.discoverServices(nil)
                            foundConnected = true
                        }
                    }
                }
                if foundConnected { return }
            }
            
            // Also try retrieving ALL connected peripherals and log them
            let allConnected = self.centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: "180A")])
            log.info("All connected peripherals (Device Info service): \(allConnected.map { $0.name ?? "?" })")
            for p in allConnected {
                let pName = p.name ?? ""
                log.info("  Connected peripheral: '\(pName)'")
                if !pName.isEmpty && !foundConnected {
                    // Try connecting to any named peripheral
                    if G2Constants.isG2Device(name: pName) || pName.lowercased().contains("pair") || pName.lowercased().contains("even") {
                        log.info("  -> Looks like G2! Connecting...")
                        self.peripheral = p
                        p.delegate = self
                        self.state = .connecting
                        p.discoverServices(nil)
                        foundConnected = true
                    }
                }
            }
            if foundConnected { return }

            // Fallback: scan for advertising G2 devices
            log.info("Scanning for Even G2 glasses...")
            // Scan for G2 service UUID AND scan all (some G2s don't advertise the custom service)
            self.centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        // Start scan timeout
        scanTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
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
        let name = peripheral.name ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasG2Service = advertisedServices.contains(G2Constants.serviceUUID)
        
        // Accept if: has G2 service UUID, OR name matches known G2 patterns
        let nameMatch = !name.isEmpty && (
            G2Constants.isG2Device(name: name) ||
            name.lowercased().contains("even") ||
            name.lowercased().contains("pair")
        )
        
        guard hasG2Service || nameMatch else { return }
        log.info("G2 candidate found: '\(name)' service=\(hasG2Service) RSSI=\(RSSI)")

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
        peripheral.discoverServices(nil) // Discover ALL services
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

// MARK: - Protobuf Parser

/// Simple protobuf parser for ConversateMessage without needing full protobuf library
struct ConversateParser {
    
    static func parseConversateMessage(_ data: Data) -> (text: String, isFinal: Bool)? {
        var offset = 0
        
        // Look for field 7 (ConversateTranscript) - tag 0x3A (7 << 3 | 2)
        while offset < data.count {
            guard offset + 1 < data.count else { break }
            
            let tag = data[offset]
            offset += 1
            
            if tag == 0x3A { // Field 7, wire type 2 (length-delimited)
                // Read length varint
                guard let (length, lengthBytes) = readVarint(data, offset: offset) else { return nil }
                offset += lengthBytes
                
                guard offset + Int(length) <= data.count else { return nil }
                
                // Parse ConversateTranscript fields within this length
                let transcriptData = data.subdata(in: offset..<(offset + Int(length)))
                return parseConversateTranscript(transcriptData)
            } else {
                // Skip unknown field - need to handle different wire types
                offset = skipField(data, offset: offset - 1) ?? data.count
            }
        }
        
        return nil
    }
    
    private static func parseConversateTranscript(_ data: Data) -> (text: String, isFinal: Bool)? {
        var offset = 0
        var text = ""
        var isFinal = false
        
        while offset < data.count {
            guard offset < data.count else { break }
            
            let tag = data[offset]
            offset += 1
            
            switch tag {
            case 0x0A: // Field 1 (text), wire type 2 (string)
                guard let (length, lengthBytes) = readVarint(data, offset: offset) else { continue }
                offset += lengthBytes
                
                guard offset + Int(length) <= data.count else { continue }
                
                if let textValue = String(data: data.subdata(in: offset..<(offset + Int(length))), encoding: .utf8) {
                    text = textValue
                }
                offset += Int(length)
                
            case 0x10: // Field 2 (is_final), wire type 0 (varint/bool)
                guard let (value, valueBytes) = readVarint(data, offset: offset) else { continue }
                isFinal = value != 0
                offset += valueBytes
                
            default:
                // Skip unknown field
                offset = skipField(data, offset: offset - 1) ?? data.count
            }
        }
        
        return (text: text, isFinal: isFinal)
    }
    
    private static func readVarint(_ data: Data, offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift = 0
        var bytesRead = 0
        
        for i in offset..<data.count {
            let byte = data[i]
            bytesRead += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 { // MSB is 0, end of varint
                return (result, bytesRead)
            }
            
            shift += 7
            if shift >= 64 { return nil } // Overflow protection
        }
        
        return nil // Incomplete varint
    }
    
    private static func skipField(_ data: Data, offset: Int) -> Int? {
        guard offset < data.count else { return nil }
        
        let tag = data[offset]
        let wireType = tag & 0x07
        var newOffset = offset + 1
        
        switch wireType {
        case 0: // Varint
            guard let (_, bytes) = readVarint(data, offset: newOffset) else { return nil }
            newOffset += bytes
        case 1: // 64-bit
            newOffset += 8
        case 2: // Length-delimited
            guard let (length, bytes) = readVarint(data, offset: newOffset) else { return nil }
            newOffset += bytes + Int(length)
        case 5: // 32-bit
            newOffset += 4
        default:
            return nil // Unknown wire type
        }
        
        return newOffset
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
