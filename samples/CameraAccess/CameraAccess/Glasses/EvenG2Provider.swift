// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenG2Provider.swift
//
// Full GlassesProvider for Even Realities G2 smart glasses using the
// reverse-engineered BLE protocol (github.com/i-soxi/even-g2-protocol).
//
// Capabilities:
//   - Display: teleprompter text via service 0x06-20 (rich text, ~200 chars visible)
//   - Audio: G2 has mic + speakers but audio routing requires further RE work;
//            currently falls back to iPhone mic/speaker
//   - Camera: None (G2 has no camera) — always uses iPhone
//   - Input: TouchBar gestures detected via BLE notifications (tap, hold, swipe)
//
// Protocol flow:
//   1. BLE scan for "Even G2_XX_L_YYYYYY" devices
//   2. Connect to service 00002760-08c2-11e1-9073-0e8ac72e0000
//   3. Subscribe to 0x5402 (notify), write to 0x5401 (commands)
//   4. 7-packet auth handshake
//   5. Display config → teleprompter init → content pages → sync

import Foundation
import CoreBluetooth
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "G2Provider")

class EvenG2Provider: NSObject, GlassesProvider {

    // MARK: - Capabilities

    let displayCapability: DisplayCapability = .richText(maxChars: 250)
    let audioCapability: AudioCapability = .phoneOnly  // TODO: BLE audio RE needed
    let cameraCapability: CameraCapability = .phoneOnly
    let inputCapability: InputCapability = .touchpad

    // MARK: - Connection State

    private(set) var connectionState: GlassesConnectionState = .disconnected {
        didSet {
            if connectionState != oldValue {
                onConnectionStateChanged?(connectionState)
            }
        }
    }

    var onConnectionStateChanged: ((GlassesConnectionState) -> Void)?
    var onGesture: ((GlassesGesture) -> Void)?
    var onVoiceTranscription: ((String, Bool) -> Void)?
    
    // MARK: - Voice Transcription (Override)
    
    private var _onVoiceTranscription: ((String, Bool) -> Void)?
    var onVoiceTranscription: ((String, Bool) -> Void)? {
        get { _onVoiceTranscription }
        set { _onVoiceTranscription = newValue }
    }

    // MARK: - BLE

    private let bleManager = G2BLEManager()
    private var isDisplayActive = false

    // MARK: - Init

    override init() {
        super.init()
        bleManager.delegate = self
    }

    // MARK: - GlassesProvider

    func connect() async throws {
        connectionState = .connecting
        log.info("Connecting to Even G2...")

        do {
            try await bleManager.connectToGlasses()
            connectionState = .connected
            log.info("Even G2 connected and authenticated")
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() {
        bleManager.disconnect()
        isDisplayActive = false
        connectionState = .disconnected
    }

    /// Display text on the G2 via teleprompter protocol.
    func displayText(_ text: String, style: DisplayStyle) async throws {
        guard case .connected = connectionState else {
            throw G2Error.notConnected
        }

        let cleanText = HUDFormatter.stripMarkdown(text)
        let pages = G2TextFormatter.formatText(cleanText)
        let totalLines = G2TextFormatter.lineCount(for: cleanText)

        log.info("Displaying \(pages.count) pages (\(totalLines) lines)")

        // Step 1: Wake display
        let wakeSeq = bleManager.nextSeq()
        let wakeMsgID = bleManager.nextMsgID()
        bleManager.sendPacket(G2PacketBuilder.buildDisplayWake(seq: wakeSeq, msgID: wakeMsgID))
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Step 2: Display config
        let configSeq = bleManager.nextSeq()
        let configMsgID = bleManager.nextMsgID()
        bleManager.sendPacket(G2PacketBuilder.buildDisplayConfig(seq: configSeq, msgID: configMsgID))
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Step 3: Teleprompter init
        let initSeq = bleManager.nextSeq()
        let initMsgID = bleManager.nextMsgID()
        bleManager.sendPacket(G2PacketBuilder.buildTeleprompterInit(
            seq: initSeq, msgID: initMsgID,
            totalLines: totalLines, manualMode: true
        ))
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Step 4: Content pages 0-9
        for i in 0..<min(10, pages.count) {
            let seq = bleManager.nextSeq()
            let msgID = bleManager.nextMsgID()
            bleManager.sendPacket(G2PacketBuilder.buildContentPage(
                seq: seq, msgID: msgID, pageNum: i, text: pages[i]
            ))
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Step 5: Mid-stream marker
        if pages.count > 10 {
            let markerSeq = bleManager.nextSeq()
            let markerMsgID = bleManager.nextMsgID()
            bleManager.sendPacket(G2PacketBuilder.buildMarker(seq: markerSeq, msgID: markerMsgID))
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Step 6: Pages 10-11
        for i in 10..<min(12, pages.count) {
            let seq = bleManager.nextSeq()
            let msgID = bleManager.nextMsgID()
            bleManager.sendPacket(G2PacketBuilder.buildContentPage(
                seq: seq, msgID: msgID, pageNum: i, text: pages[i]
            ))
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Step 7: Sync trigger
        let syncSeq = bleManager.nextSeq()
        let syncMsgID = bleManager.nextMsgID()
        bleManager.sendPacket(G2PacketBuilder.buildSync(seq: syncSeq, msgID: syncMsgID))
        try await Task.sleep(nanoseconds: 50_000_000)

        // Step 8: Remaining pages (12+)
        for i in 12..<pages.count {
            let seq = bleManager.nextSeq()
            let msgID = bleManager.nextMsgID()
            bleManager.sendPacket(G2PacketBuilder.buildContentPage(
                seq: seq, msgID: msgID, pageNum: i, text: pages[i]
            ))
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        isDisplayActive = true
        log.info("Display content sent successfully")
    }

    func clearDisplay() async throws {
        guard case .connected = connectionState else {
            throw G2Error.notConnected
        }
        // Send empty content to clear
        let emptyPages = G2TextFormatter.formatText(" ")
        let seq = bleManager.nextSeq()
        let msgID = bleManager.nextMsgID()
        bleManager.sendPacket(G2PacketBuilder.buildTeleprompterInit(
            seq: seq, msgID: msgID, totalLines: 1, manualMode: true
        ))
        for (i, page) in emptyPages.enumerated() {
            let s = bleManager.nextSeq()
            let m = bleManager.nextMsgID()
            bleManager.sendPacket(G2PacketBuilder.buildContentPage(
                seq: s, msgID: m, pageNum: i, text: page
            ))
        }
        isDisplayActive = false
    }
}

// MARK: - G2BLEManagerDelegate

extension EvenG2Provider: G2BLEManagerDelegate {

    func bleManager(_ manager: G2BLEManager, didChangeState state: G2BLEManager.State) {
        switch state {
        case .idle:
            connectionState = .disconnected
        case .scanning, .connecting, .authenticating:
            connectionState = .connecting
        case .connected:
            connectionState = .connected
        case .disconnected:
            connectionState = .disconnected
        case .error(let msg):
            connectionState = .error(msg)
        }
    }

    func bleManager(_ manager: G2BLEManager, didReceiveData data: Data) {
        // Parse response packets from glasses
        guard data.count >= G2Constants.headerSize + 2 else { return }
        let type = data[1]
        guard type == G2Constants.typeResponse else { return }

        let serviceHi = data[6]
        let serviceLo = data[7]

        log.debug("Response: svc=0x\(String(format: "%02X", serviceHi))-\(String(format: "%02X", serviceLo)) len=\(data.count)")

        // TouchBar gesture events (based on protocol analysis)
        if serviceHi == 0x09 && serviceLo == 0x20 {
            parseGestureResponse(data)
        }
        // Alternative gesture service (some G2 variants use different IDs)
        else if serviceHi == 0x08 && serviceLo == 0x20 {
            parseGestureResponse(data)
        }
        // Conversate service (0x0B-20) — voice transcription from glasses mic
        else if serviceHi == 0x0B && serviceLo == 0x20 {
            parseConversateResponse(data)
        }
    }

    func bleManager(_ manager: G2BLEManager, didDiscoverDevice name: String, rssi: NSNumber) {
        log.info("Discovered: \(name) RSSI=\(rssi)")
    }
    
    func bleManager(_ manager: G2BLEManager, didReceiveVoiceTranscript text: String, isFinal: Bool) {
        onVoiceTranscription?(text, isFinal)
    }

    // MARK: - Gesture Parsing

    /// Parse TouchBar gesture events from G2.
    /// Service 0x09-20 or 0x08-20 depending on G2 variant.
    private func parseGestureResponse(_ data: Data) {
        // Payload starts at byte 8, before CRC (last 2 bytes)
        guard data.count > G2Constants.headerSize + 2 else { return }
        let payload = data.subdata(in: G2Constants.headerSize..<(data.count - 2))
        
        log.info("Gesture data: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Parse gesture type from payload
        // This is based on reverse engineering - may need adjustment for different G2 variants
        guard payload.count >= 2 else { return }
        
        let gestureType = payload[0]
        let gestureValue = payload[1]
        
        var detectedGesture: GlassesGesture?
        
        // Map gesture bytes to GlassesGesture enum
        // These mappings may need adjustment based on actual G2 protocol
        switch gestureType {
        case 0x01: // Single tap
            if gestureValue == 0x01 {
                detectedGesture = .tap
            }
        case 0x02: // Double tap
            if gestureValue == 0x01 {
                detectedGesture = .doubleTap
            }
        case 0x03: // Swipe forward
            if gestureValue == 0x01 {
                detectedGesture = .swipeForward
            }
        case 0x04: // Swipe backward
            if gestureValue == 0x01 {
                detectedGesture = .swipeBackward
            }
        case 0x05: // Long press/hold
            if gestureValue == 0x01 {
                detectedGesture = .longPress
            }
        default:
            log.debug("Unknown gesture type: 0x\(String(format: "%02X", gestureType))")
        }
        
        if let gesture = detectedGesture {
            log.info("Detected gesture: \(gesture)")
            onGesture?(gesture)
        }
    }

    // MARK: - Conversate Parsing

    /// Parse Conversate (0x0B-20) speech transcription responses.
    /// This is how the G2's 4-mic array sends transcribed voice to the phone.
    private func parseConversateResponse(_ data: Data) {
        // Payload starts at byte 8, before CRC (last 2 bytes)
        guard data.count > G2Constants.headerSize + 2 else { return }
        let payload = data.subdata(in: G2Constants.headerSize..<(data.count - 2))

        log.info("Conversate data: \(payload.count) bytes - \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Parse ConversateMessage protobuf
        if let (text, isFinal) = ConversateParser.parseConversateMessage(payload) {
            log.info("Conversate transcript: '\(text)' (final: \(isFinal))")
            onVoiceTranscription?(text, isFinal)
        } else {
            log.warning("Failed to parse Conversate message")
        }
    }
}
