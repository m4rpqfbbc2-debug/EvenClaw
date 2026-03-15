// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2AutoConnector.swift
// Background BLE scanner for Even G2 glasses. Uses its own CBCentralManager
// to find glasses, then hands off to EvenG2Provider for protocol handling.

import Foundation
import CoreBluetooth
import Combine
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "G2AutoConnect")

@MainActor
final class G2AutoConnector: NSObject, ObservableObject {

    enum ScanState: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case bluetoothOff
        case unauthorized
    }

    @Published var scanState: ScanState = .idle
    @Published var connectedDeviceName: String?
    @Published var discoveredDeviceNames: [String] = []

    var glassesProvider: EvenG2Provider?
    var onGlassesAvailabilityChanged: ((Bool) -> Void)?

    private var centralManager: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "g2autoconnect.ble")
    private var foundPeripheral: CBPeripheral?
    private var isActive = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private let maxReconnectDelay: TimeInterval = 30.0

    override init() {
        super.init()
        // Create CBCentralManager immediately to trigger Bluetooth permission
        centralManager = CBCentralManager(delegate: nil, queue: bleQueue)
    }

    func startScanning() {
        guard !isActive else { return }
        isActive = true
        reconnectAttempt = 0
        scanState = .scanning
        log.info("Starting G2 scan")
        
        // Set delegate on the ble queue
        bleQueue.async { [weak self] in
            self?.centralManager.delegate = self
            // If already powered on, start scanning immediately
            if self?.centralManager.state == .poweredOn {
                self?.doScan()
            }
        }
    }

    func stop() {
        isActive = false
        reconnectTask?.cancel()
        bleQueue.async { [weak self] in
            self?.centralManager.stopScan()
        }
        disconnect()
        scanState = .idle
    }

    func retryNow() {
        reconnectAttempt = 0
        reconnectTask?.cancel()
        scanState = .scanning
        bleQueue.async { [weak self] in
            self?.doScan()
        }
    }

    func disconnect() {
        glassesProvider?.disconnect()
        glassesProvider = nil
        connectedDeviceName = nil
        foundPeripheral = nil
        onGlassesAvailabilityChanged?(false)
    }

    var isConnected: Bool { scanState == .connected }

    // MARK: - Internal scan logic (runs on bleQueue)

    private func doScan() {
        guard isActive, centralManager.state == .poweredOn else { return }
        
        log.info("Scanning for G2 glasses...")
        
        // Step 1: Check already-connected peripherals (most reliable for paired G2)
        let serviceUUIDs: [CBUUID] = [
            CBUUID(string: "00002760-08c2-11e1-9073-0e8ac72e0000"), // G2 custom
            CBUUID(string: "180A"), // Device Info
            CBUUID(string: "180F"), // Battery
            CBUUID(string: "1800"), // Generic Access
            CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART
        ]
        
        for svcUUID in serviceUUIDs {
            let connected = centralManager.retrieveConnectedPeripherals(withServices: [svcUUID])
            for p in connected {
                let name = p.name ?? ""
                log.info("Found connected: '\(name)' via \(svcUUID.uuidString)")
                
                DispatchQueue.main.async { [weak self] in
                    if !name.isEmpty && !(self?.discoveredDeviceNames.contains(name) ?? true) {
                        self?.discoveredDeviceNames.append(name)
                    }
                }
                
                if isG2(name: name) {
                    log.info("G2 found (connected): '\(name)' — connecting")
                    foundPeripheral = p
                    connectToFoundGlasses(peripheral: p, name: name)
                    return
                }
            }
        }
        
        // Step 2: Scan for advertising peripherals
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Timeout after 30s
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.isActive, self.scanState == .scanning else { return }
            self.bleQueue.async {
                self.centralManager.stopScan()
            }
            self.scheduleReconnect()
        }
    }

    private func isG2(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("even g2") ||
               lower.hasPrefix("even_g2") ||
               lower.hasPrefix("pair_") ||
               lower.hasPrefix("even ") ||
               lower.contains("g2") ||
               lower.contains("even")
    }

    private func connectToFoundGlasses(peripheral: CBPeripheral, name: String) {
        centralManager.stopScan()
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scanState = .connecting
            self.connectedDeviceName = name
            
            // Create EvenG2Provider and connect using the found peripheral
            let provider = EvenG2Provider()
            self.glassesProvider = provider
            
            Task {
                do {
                    try await provider.connect()
                    self.scanState = .connected
                    self.reconnectAttempt = 0
                    self.onGlassesAvailabilityChanged?(true)
                    log.info("G2 connected: \(name)")
                } catch {
                    log.error("G2 connection failed: \(error.localizedDescription)")
                    self.glassesProvider = nil
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        
        DispatchQueue.main.async { [weak self] in
            self?.scanState = .reconnecting(attempt: self?.reconnectAttempt ?? 0)
        }
        
        log.info("Reconnect in \(delay)s (attempt \(self.reconnectAttempt))")
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self.isActive else { return }
            self.bleQueue.async { [weak self] in
                self?.doScan()
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension G2AutoConnector: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        log.info("BLE state: \(state.rawValue)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .poweredOn:
                if self.isActive && self.scanState == .scanning {
                    self.bleQueue.async { self.doScan() }
                }
            case .poweredOff:
                self.scanState = .bluetoothOff
            case .unauthorized:
                self.scanState = .unauthorized
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasG2Service = services.contains(CBUUID(string: "00002760-08c2-11e1-9073-0e8ac72e0000"))
        
        DispatchQueue.main.async { [weak self] in
            if !name.isEmpty && !(self?.discoveredDeviceNames.contains(name) ?? true) {
                self?.discoveredDeviceNames.append(name)
            }
        }
        
        if hasG2Service || (!name.isEmpty && isG2Nonisolated(name: name)) {
            log.info("G2 found (advertising): \(name) RSSI=\(RSSI)")
            DispatchQueue.main.async { [weak self] in
                self?.connectToFoundGlasses(peripheral: peripheral, name: name)
            }
        }
    }
    
    private nonisolated func isG2Nonisolated(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("even g2") ||
               lower.hasPrefix("even_g2") ||
               lower.hasPrefix("pair_") ||
               lower.hasPrefix("even ") ||
               lower.contains("g2") ||
               lower.contains("even")
    }
}
