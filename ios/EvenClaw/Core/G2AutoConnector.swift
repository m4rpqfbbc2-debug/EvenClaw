// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2AutoConnector.swift
// Background BLE scanner for Even G2 glasses. Scans, auto-connects, and
// reconnects with exponential backoff. Never blocks UI.

import Foundation
import CoreBluetooth
import Combine
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "G2AutoConnect")

@MainActor
final class G2AutoConnector: ObservableObject {

    // MARK: - Published State

    enum ScanState: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case bluetoothOff
        case unauthorized
    }

    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var connectedDeviceName: String?

    /// The active glasses provider — nil when not connected.
    private(set) var glassesProvider: EvenG2Provider?

    /// Callback when glasses connect/disconnect.
    var onGlassesAvailabilityChanged: ((Bool) -> Void)?

    // MARK: - Reconnect Config

    private let baseReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var isActive = false

    // MARK: - Public API

    /// Start background scanning for G2 glasses. Safe to call multiple times.
    func startScanning() {
        guard !isActive else { return }
        isActive = true
        reconnectAttempt = 0
        log.info("G2 auto-connector starting")
        attemptConnection()
    }

    /// Stop scanning and disconnect.
    func stop() {
        isActive = false
        scanTask?.cancel()
        scanTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        disconnect()
        scanState = .idle
        log.info("G2 auto-connector stopped")
    }

    /// Manually trigger a reconnect attempt.
    func retryNow() {
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        attemptConnection()
    }

    /// Disconnect glasses (user-initiated or internal).
    func disconnect() {
        glassesProvider?.disconnect()
        glassesProvider = nil
        connectedDeviceName = nil
        if scanState == .connected {
            scanState = .idle
        }
        onGlassesAvailabilityChanged?(false)
    }

    var isConnected: Bool {
        scanState == .connected
    }

    // MARK: - Connection Logic

    private func attemptConnection() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self, self.isActive else { return }

            self.scanState = self.reconnectAttempt > 0
                ? .reconnecting(attempt: self.reconnectAttempt)
                : .scanning

            let provider = EvenG2Provider()

            provider.onConnectionStateChanged = { [weak self] connState in
                Task { @MainActor in
                    self?.handleConnectionStateChange(connState)
                }
            }

            do {
                try await provider.connect()
                guard !Task.isCancelled, self.isActive else {
                    provider.disconnect()
                    return
                }
                self.glassesProvider = provider
                self.connectedDeviceName = "Even G2"
                self.scanState = .connected
                self.reconnectAttempt = 0
                self.onGlassesAvailabilityChanged?(true)
                log.info("G2 auto-connected successfully")
            } catch {
                guard !Task.isCancelled, self.isActive else { return }
                log.warning("G2 connection attempt failed: \(error.localizedDescription)")
                self.scheduleReconnect()
            }
        }
    }

    private func handleConnectionStateChange(_ connState: GlassesConnectionState) {
        switch connState {
        case .disconnected:
            guard isActive, scanState == .connected else { return }
            log.info("G2 disconnected — scheduling reconnect")
            glassesProvider = nil
            connectedDeviceName = nil
            onGlassesAvailabilityChanged?(false)
            scheduleReconnect()
        case .error(let msg):
            guard isActive else { return }
            log.error("G2 connection error: \(msg)")
            glassesProvider = nil
            connectedDeviceName = nil
            onGlassesAvailabilityChanged?(false)
            scheduleReconnect()
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectAttempt += 1
        let delay = min(
            baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)),
            maxReconnectDelay
        )
        scanState = .reconnecting(attempt: reconnectAttempt)
        log.info("Reconnect attempt \(self.reconnectAttempt) in \(delay)s")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.attemptConnection()
        }
    }
}
