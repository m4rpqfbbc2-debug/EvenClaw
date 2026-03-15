// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2AutoConnector.swift
// Owns the ONE CBCentralManager for the entire app. Scans for G2 glasses,
// connects, then hands the peripheral to G2BLEManager for protocol handling.
// CoreBluetooth rule: only the CBCentralManager that discovered/connected a
// peripheral can interact with it — so everything flows through this class.

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

    private(set) var glassesProvider: EvenG2Provider?
    var onGlassesAvailabilityChanged: ((Bool) -> Void)?

    // The ONE central manager for the whole app
    private var centralManager: CBCentralManager!
    private var foundPeripheral: CBPeripheral?
    private var isActive = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?
    private let maxReconnectDelay: TimeInterval = 30.0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: nil, queue: nil)
    }

    // MARK: - Public API

    func startScanning() {
        guard !isActive else { return }
        isActive = true
        reconnectAttempt = 0
        scanState = .scanning
        log.info("Starting G2 scan")

        centralManager.delegate = self
        if centralManager.state == .poweredOn {
            doScan()
        }
    }

    func stop() {
        isActive = false
        reconnectTask?.cancel()
        scanTimeoutTask?.cancel()
        centralManager.stopScan()
        disconnect()
        scanState = .idle
    }

    func retryNow() {
        reconnectAttempt = 0
        reconnectTask?.cancel()
        scanTimeoutTask?.cancel()
        scanState = .scanning
        doScan()
    }

    func disconnect() {
        glassesProvider?.disconnect()
        glassesProvider = nil
        if let p = foundPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        foundPeripheral = nil
        connectedDeviceName = nil
        onGlassesAvailabilityChanged?(false)
    }

    var isConnected: Bool { scanState == .connected }

    // MARK: - Scan Logic (runs on bleQueue)

    private func doScan() {
        guard isActive, centralManager.state == .poweredOn else { return }

        log.info("Scanning for G2 glasses...")

        // Step 1: Check already-connected peripherals across multiple services
        let serviceUUIDs: [CBUUID] = [
            G2Constants.serviceUUID,
            CBUUID(string: "180A"),
            CBUUID(string: "180F"),
            CBUUID(string: "1800"),
            CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
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

                if Self.isG2(name: name) {
                    log.info("G2 found (already connected): '\(name)'")
                    handleFoundG2(peripheral: p, name: name, alreadyConnected: true)
                    return
                }
            }
        }

        // Step 2: Active scan for advertising peripherals
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Timeout after 30s
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, self.isActive else { return }
            if case .scanning = self.scanState {
                self.centralManager.stopScan()
                self.scheduleReconnect()
            }
        }
    }

    private func handleFoundG2(peripheral: CBPeripheral, name: String, alreadyConnected: Bool) {
        centralManager.stopScan()
        scanTimeoutTask?.cancel()
        foundPeripheral = peripheral
        scanState = .connecting
        connectedDeviceName = name

        if alreadyConnected {
            runG2Protocol(on: peripheral, name: name)
        } else {
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Create G2BLEManager + EvenG2Provider and run auth on the connected peripheral.
    private func runG2Protocol(on peripheral: CBPeripheral, name: String) {
        let bleManager = G2BLEManager(centralManager: centralManager)
        let provider = EvenG2Provider(bleManager: bleManager)
        self.glassesProvider = provider

        Task {
            do {
                try await provider.connectKnown(peripheral: peripheral)
                self.scanState = .connected
                self.reconnectAttempt = 0
                self.onGlassesAvailabilityChanged?(true)
                log.info("G2 fully connected + authenticated: \(name)")
            } catch {
                log.error("G2 protocol failed: \(error.localizedDescription)")
                self.glassesProvider = nil
                self.scheduleReconnect()
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)

        scanState = .reconnecting(attempt: reconnectAttempt)
        log.info("Reconnect in \(delay)s (attempt \(self.reconnectAttempt))")

        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, self.isActive else { return }
            self.scanState = .scanning
            self.doScan()
        }
    }

    // MARK: - Name Matching

    nonisolated static func isG2(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("even g2") ||
               lower.hasPrefix("even_g2") ||
               lower.hasPrefix("pair_") ||
               lower.hasPrefix("even ") ||
               lower.contains("g2") ||
               lower.contains("even")
    }
}

// MARK: - CBCentralManagerDelegate

extension G2AutoConnector: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        log.info("BLE state: \(state.rawValue)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .poweredOn:
                if self.isActive {
                    if case .scanning = self.scanState {
                        self.doScan()
                    } else if case .bluetoothOff = self.scanState {
                        self.scanState = .scanning
                        self.doScan()
                    }
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
        let hasG2Service = services.contains(G2Constants.serviceUUID)

        Task { @MainActor [weak self] in
            if !name.isEmpty && !(self?.discoveredDeviceNames.contains(name) ?? true) {
                self?.discoveredDeviceNames.append(name)
            }
        }

        if hasG2Service || (!name.isEmpty && Self.isG2(name: name)) {
            log.info("G2 found (advertising): '\(name)' RSSI=\(RSSI)")
            if G2Constants.isLeftEar(name: name) || !name.contains("_R_") {
                Task { @MainActor [weak self] in
                    self?.handleFoundG2(peripheral: peripheral, name: name, alreadyConnected: false)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("CoreBluetooth connected: '\(peripheral.name ?? "?")'")
        let name = peripheral.name ?? "Even G2"

        Task { @MainActor [weak self] in
            self?.runG2Protocol(on: peripheral, name: name)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "Unknown error"
        log.error("Connection failed: \(msg)")

        Task { @MainActor [weak self] in
            self?.foundPeripheral = nil
            self?.scheduleReconnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Disconnected: \(error?.localizedDescription ?? "clean")")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.foundPeripheral = nil
            self.glassesProvider = nil
            self.connectedDeviceName = nil
            self.onGlassesAvailabilityChanged?(false)

            if self.isActive {
                self.scheduleReconnect()
            } else {
                self.scanState = .idle
            }
        }
    }
}
