// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2Sniffer.swift
// Thin coordinator: owns BLE connection, packet logging, and protocol parsing.
// Delegates orchestration to EvenClawController, ConversationManager.

import Foundation
import CoreBluetooth
import os.log
import Speech
import AVFoundation

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Sniffer")

// MARK: - Packet Log Entry

struct PacketLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let direction: String
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
        case (0x07, 0x20): return "\(svc) EvenAI"
        case (0x07, 0x00): return "\(svc) EvenAI←"
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

    var hexDump: String { rawData.map { String(format: "%02X", $0) }.joined(separator: " ") }
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
    @Published var evenAIActive = false
    @Published var lastQuestion = ""
    @Published var lastAnswer = ""
    @Published var isListening = false
    @Published var audioLevel: Float = 0
    @Published var audioLevelHistory: [Float] = Array(repeating: 0, count: 30)
    @Published var micStatus = "Waiting for TouchBar..."
    @Published var wakeWordActive = false
    @Published var headGestureActive = false
    @Published var headGestureSource = "none"
    @Published var isProcessing = false

    var snifferOwnRecording = false

    // MARK: - Phase 2: State Machine + Gesture Controller
    let appState = AppStateMachine()
    let gestureController = GestureController()

    // MARK: - TouchBar Double-Tap Detection
    private var lastTapTime: Date?
    private var tapStartTime: Date?
    private let doubleTapWindow: TimeInterval = 0.6
    private let maxTapDuration: TimeInterval = 0.4

    // MARK: - Managers (extracted from monolithic G2Sniffer)
    private var controller: EvenClawController!
    private var conversationManager: ConversationManager!

    // G2 Microphone System
    private var g2BLEManager: G2BLEManager?
    var voiceCommandManager: VoiceCommandManager?

    private var centralManager: CBCentralManager!
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    @Published var liveTranscript = ""
    private var seq: UInt8 = 0x08
    private var magic: UInt8 = 100
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

        g2BLEManager = G2BLEManager()
        let glassesProvider = EvenG2Provider()
        voiceCommandManager = VoiceCommandManager(glassesProvider: glassesProvider)

        g2BLEManager?.delegate = self
        voiceCommandManager?.setBLEManager(g2BLEManager!)

        // Phase 2: Wire gesture controller to state machine
        gestureController.stateMachine = appState
        appState.delegate = self

        conversationManager = ConversationManager(sniffer: self)
        controller = EvenClawController(
            sniffer: self,
            voiceCommandManager: voiceCommandManager!,
            g2BLEManager: g2BLEManager!
        )

        NSLog("[Sniffer] About to call VCM setup()")
        Task { [weak self] in
            NSLog("[Sniffer] Task started, calling setup()")
            await self?.voiceCommandManager?.setup()
            NSLog("[Sniffer] VCM setup() complete")
        }
    }

    // MARK: - Public API

    func connectAndAuth() async {
        statusMessage = "Scanning for G2..."
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
            await enterEvenAIMode()
            statusMessage = "Ready. Say 'Hey Aisha' to talk to OpenClaw"
            let bridge = OpenClawBridge()
            await bridge.checkConnection()
            openClawConnected = bridge.connectionState == .connected
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        if let p = peripheral { centralManager.cancelPeripheralConnection(p) }
        peripheral = nil; writeChar = nil; notifyChar = nil
        bleConnected = false; authenticated = false
        statusMessage = "Disconnected"
    }

    func clearLog() {
        packetLog.removeAll(); packetCount = 0
        conversateText = ""; conversateFinal = false
    }

    func exportLog() -> String {
        packetLog.map { e in
            "\(e.timestamp) \(e.direction) \(e.serviceLabel) (\(e.size)B): \(e.hexDump)" +
            (e.parsedContent.map { " → \($0)" } ?? "")
        }.joined(separator: "\n")
    }

    // MARK: - Double-Tap Dismiss

    private func handleDoubleTapDismiss() {
        conversationManager.handleDoubleTapDismiss()
        controller.updateMicStatus()
    }

    // MARK: - Even AI Protocol

    func enterEvenAIMode() async {
        guard let writeChar, let peripheral, authenticated else {
            statusMessage = "Not connected/authenticated"; return
        }
        statusMessage = "Entering Even AI mode..."
        let pkt = G2PacketBuilder.buildEvenAIEnter(seq: nextSeq(), magic: nextMagic())
        peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
        logPacket(direction: "TX", data: pkt)
        try? await Task.sleep(nanoseconds: 300_000_000)
        evenAIActive = true
        statusMessage = "Even AI mode active ✨"
    }

    func exitEvenAIMode() async {
        guard let writeChar, let peripheral else { return }
        let pkt = G2PacketBuilder.buildEvenAIExit(seq: nextSeq(), magic: nextMagic())
        peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
        logPacket(direction: "TX", data: pkt)
        evenAIActive = false; statusMessage = "Even AI mode exited"
    }

    func sendQuestion(_ text: String) async {
        guard let writeChar, let peripheral, evenAIActive else {
            if !evenAIActive { await enterEvenAIMode() }
            guard let wc = self.writeChar, let p = self.peripheral else { return }
            let pkt = G2PacketBuilder.buildEvenAIAsk(seq: nextSeq(), magic: nextMagic(), text: text)
            p.writeValue(pkt, for: wc, type: .withoutResponse)
            logPacket(direction: "TX", data: pkt); lastQuestion = text; return
        }
        let pkt = G2PacketBuilder.buildEvenAIAsk(seq: nextSeq(), magic: nextMagic(), text: text)
        peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
        logPacket(direction: "TX", data: pkt); lastQuestion = text
    }

    func sendReply(_ text: String) async {
        guard let writeChar, let peripheral else { return }
        if !evenAIActive { await enterEvenAIMode() }
        let chunks = chunkTextForHUD(text, maxChars: 60)
        lastAnswer = text

        if chunks.count <= 1 {
            let pkt = G2PacketBuilder.buildEvenAIReply(seq: nextSeq(), magic: nextMagic(), text: text)
            peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
            logPacket(direction: "TX", data: pkt); return
        }

        let m = nextMagic()
        let startPkt = G2PacketBuilder.buildEvenAIReplyStreamStart(seq: nextSeq(), magic: m)
        peripheral.writeValue(startPkt, for: writeChar, type: .withoutResponse)
        logPacket(direction: "TX", data: startPkt)

        for (i, chunk) in chunks.enumerated() {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if i < chunks.count - 1 {
                let pkt = G2PacketBuilder.buildEvenAIReplyStreamChunk(seq: nextSeq(), magic: m, cmdCnt: i + 1, text: chunk)
                peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
                logPacket(direction: "TX", data: pkt)
            } else {
                let pkt = G2PacketBuilder.buildEvenAIReplyStreamEnd(seq: nextSeq(), magic: m, cmdCnt: i + 1, text: chunk)
                peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
                logPacket(direction: "TX", data: pkt)
            }
        }
    }

    private func chunkTextForHUD(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []; var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxChars {
                if !current.isEmpty { chunks.append(current) }
                current = String(word.prefix(maxChars))
            } else { current = candidate }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func askOpenClaw(_ question: String) async {
        await conversationManager.askOpenClaw(question)
    }

    private func nextSeq() -> UInt8 { seq &+= 1; return seq }
    private func nextMagic() -> UInt8 { magic &+= 1; return magic }

    func testHUD() async {
        guard let writeChar, let peripheral else { return }
        if !evenAIActive { await enterEvenAIMode() }
        let pkt = G2PacketBuilder.buildEvenAIReply(seq: nextSeq(), magic: nextMagic(), text: "HUD test from EvenClaw")
        peripheral.writeValue(pkt, for: writeChar, type: .withoutResponse)
        logPacket(direction: "TX", data: pkt); statusMessage = "Test sent to HUD"
    }

    // MARK: - Voice Input

    func requestSpeechPermission() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in cont.resume() }
        }
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func startListening() {
        guard !isListening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognition unavailable"; return
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusMessage = "Speech permission denied"; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            statusMessage = "Audio setup failed: \(error.localizedDescription)"; return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frames) { sum += abs(data[i]) }
                let avg = sum / Float(frames)
                Task { @MainActor in
                    self?.audioLevel = avg
                    self?.audioLevelHistory.append(avg)
                    if (self?.audioLevelHistory.count ?? 0) > 30 { self?.audioLevelHistory.removeFirst() }
                }
            }
        }
        do {
            audioEngine.prepare(); try audioEngine.start()
        } catch {
            statusMessage = "Mic error: \(error.localizedDescription)"; cleanupAudio(); return
        }

        isListening = true; snifferOwnRecording = true; liveTranscript = ""
        statusMessage = "Listening..."

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let s = self as? G2Sniffer, s.isListening else { return }
                if let result {
                    s.liveTranscript = result.bestTranscription.formattedString
                    s.statusMessage = "🎤 \(s.liveTranscript)"
                }
                if let error {
                    NSLog("[Speech] error: %@", error.localizedDescription)
                    if !s.liveTranscript.isEmpty { await s.stopListeningAndSend() }
                    else { s.cleanupAudio(); s.isListening = false; s.statusMessage = "Ready" }
                }
            }
        }
    }

    func stopListeningAndSend() async {
        guard isListening else { return }
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupAudio(); isListening = false; snifferOwnRecording = false
        audioLevel = 0; audioLevelHistory = Array(repeating: 0, count: 30)
        guard !text.isEmpty else { statusMessage = "Didn't catch that"; return }
        await askOpenClaw(text)
    }

    private func cleanupAudio() {
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionRequest = nil; recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Even AI Packet Parser

    private func parseEvenAIPacket(_ data: Data) -> String? {
        guard data.count > 10 else { return nil }
        let payload = data.subdata(in: 8..<(data.count - 2))
        guard payload.count >= 4 else { return nil }
        var pos = 0; var commandId: UInt8 = 0; var magicRandom: UInt8 = 0
        while pos < payload.count {
            let tag = payload[pos]; pos += 1
            let fieldNum = tag >> 3; let wireType = tag & 0x07
            if wireType == 0 {
                var value: UInt64 = 0; var shift = 0
                while pos < payload.count {
                    let b = payload[pos]; pos += 1
                    value |= UInt64(b & 0x7F) << shift; if b & 0x80 == 0 { break }; shift += 7
                }
                if fieldNum == 1 { commandId = UInt8(value) }
                if fieldNum == 2 { magicRandom = UInt8(value) }
            } else if wireType == 2 {
                guard pos < payload.count else { break }
                var length: Int = 0; var shift = 0
                while pos < payload.count {
                    let b = payload[pos]; pos += 1
                    length |= Int(b & 0x7F) << shift; if b & 0x80 == 0 { break }; shift += 7
                }
                guard pos + length <= payload.count else { break }
                let subData = payload.subdata(in: pos..<(pos + length))
                if fieldNum == 5 || fieldNum == 7 {
                    if let text = extractTextField(subData) {
                        let cmdName = commandId == 3 ? "ASK" : commandId == 5 ? "REPLY" : "CMD\(commandId)"
                        return "🤖 \(cmdName): \"\(text)\""
                    }
                }
                if fieldNum == 3, subData.count >= 2, subData[0] == 0x08 {
                    let status = subData[1]
                    let statusName = status == 1 ? "WAKE_UP" : status == 2 ? "ENTER" : status == 3 ? "EXIT" : "?\(status)"
                    return "🤖 CTRL: \(statusName)"
                }
                pos += length
            } else { break }
        }
        if commandId > 0 {
            let cmdNames = ["", "CTRL", "VAD", "ASK", "ANALYSE", "REPLY", "SKILL", "PROMPT", "EVENT", "HEARTBEAT", "CONFIG"]
            let name = Int(commandId) < cmdNames.count ? cmdNames[Int(commandId)] : "CMD\(commandId)"
            return "🤖 \(name) (magic=\(magicRandom))"
        }
        return nil
    }

    private func extractTextField(_ data: Data) -> String? {
        var pos = 0
        while pos < data.count {
            let tag = data[pos]; pos += 1
            let fieldNum = tag >> 3; let wireType = tag & 0x07
            if wireType == 0 {
                while pos < data.count { let b = data[pos]; pos += 1; if b & 0x80 == 0 { break } }
            } else if wireType == 2 {
                var length: Int = 0; var shift = 0
                while pos < data.count {
                    let b = data[pos]; pos += 1; length |= Int(b & 0x7F) << shift; if b & 0x80 == 0 { break }; shift += 7
                }
                if fieldNum == 4 {
                    guard pos + length <= data.count else { return nil }
                    return String(data: data.subdata(in: pos..<(pos + length)), encoding: .utf8)
                }
                pos += length
            } else { break }
        }
        return nil
    }

    private func extractEvenAIQuestion(_ data: Data) -> String? {
        guard data.count > 10 else { return nil }
        let payload = data.subdata(in: 8..<(data.count - 2))
        var pos = 0
        while pos < payload.count {
            let tag = payload[pos]; pos += 1
            let fieldNum = tag >> 3; let wireType = tag & 0x07
            if wireType == 0 {
                while pos < payload.count { let b = payload[pos]; pos += 1; if b & 0x80 == 0 { break } }
            } else if wireType == 2 {
                var length = 0; var shift = 0
                while pos < payload.count { let b = payload[pos]; pos += 1; length |= Int(b & 0x7F) << shift; if b & 0x80 == 0 { break }; shift += 7 }
                if fieldNum == 5 {
                    let sub = payload.subdata(in: pos..<min(pos + length, payload.count))
                    return extractTextField(sub)
                }
                pos += length
            } else { break }
        }
        return nil
    }

    // MARK: - Find & Connect

    private func findAndConnect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectContinuation = cont
            let serviceUUIDs: [CBUUID] = [
                G2Constants.serviceUUID, CBUUID(string: "180A"), CBUUID(string: "180F"),
                CBUUID(string: "1800"), CBUUID(string: "1801"),
            ]
            for svc in serviceUUIDs {
                let connected = self.centralManager.retrieveConnectedPeripherals(withServices: [svc])
                for p in connected {
                    if let name = p.name, G2Constants.isG2Device(name: name) {
                        log.info("Found paired G2: \(name)")
                        self.statusMessage = "Found \(name)"
                        self.peripheral = p; p.delegate = self
                        self.centralManager.connect(p, options: nil); return
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

    func logPacket(direction: String, data: Data) {
        var serviceHi: UInt8 = 0; var serviceLo: UInt8 = 0
        if data.count >= 8 { serviceHi = data[6]; serviceLo = data[7] }

        var parsed: String? = nil
        if data.count >= 8 && serviceHi == 0x07 && (serviceLo == 0x20 || serviceLo == 0x00) {
            parsed = parseEvenAIPacket(data)
            if serviceLo == 0x00, let p = parsed, p.contains("ASK:") {
                if let text = extractEvenAIQuestion(data) {
                    lastQuestion = text; Task { await askOpenClaw(text) }
                }
            }
        }
        if parsed == nil && data.count >= 8 && serviceHi == 0x0B && serviceLo == 0x20 && data.count > 10 {
            let payload = data.subdata(in: 8..<(data.count - 2))
            if let result = ConversateParser.parseConversateMessage(payload) {
                parsed = "💬 \"\(result.text)\" final=\(result.isFinal)"
                conversateText = result.text; conversateFinal = result.isFinal
            }
        }
        if data.count >= 8 && serviceHi == 0x11 && serviceLo == 0x20 && data.count > 10 {
            let payload = data.subdata(in: 8..<(data.count - 2))
            if let result = ConversateParser.parseConversateMessage(payload) {
                parsed = "💬 ALT \"\(result.text)\" final=\(result.isFinal)"
                conversateText = result.text; conversateFinal = result.isFinal
            }
        }

        let entry = PacketLogEntry(
            timestamp: dateFormatter.string(from: Date()),
            direction: direction, serviceHi: serviceHi, serviceLo: serviceLo,
            rawData: data, parsedContent: parsed)
        packetLog.append(entry); packetCount += 1
        if packetLog.count > 500 { packetLog.removeFirst(100) }
    }
}

// MARK: - CBCentralManagerDelegate

extension G2Sniffer: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in log.info("BLE state: \(central.state.rawValue)") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, G2Constants.isG2Device(name: name) else { return }
        Task { @MainActor in
            log.info("Found G2: \(name)"); self.statusMessage = "Found \(name)"
            central.stopScan(); self.peripheral = peripheral
            peripheral.delegate = self; central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            log.info("Connected to \(peripheral.name ?? "?")")
            self.bleConnected = true; peripheral.discoverServices(nil)
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
            self.bleConnected = false; self.authenticated = false; self.evenAIActive = false
            self.statusMessage = "Disconnected — attempting reconnect..."
            self.attemptAutoReconnect()
        }
    }
}

// MARK: - Auto-Reconnect with Exponential Backoff

extension G2Sniffer {
    private func attemptAutoReconnect(attempt: Int = 1, maxAttempts: Int = 5) {
        guard attempt <= maxAttempts else {
            statusMessage = "Reconnect failed after \(maxAttempts) attempts"
            sendHUDError("CONNECTION LOST"); return
        }
        let delay = 2.0 * pow(2.0, Double(attempt - 1))
        log.info("Auto-reconnect attempt \(attempt)/\(maxAttempts) in \(delay)s")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !self.bleConnected else { return }
            do {
                try await self.findAndConnect()
                self.statusMessage = "Reconnected. Authenticating..."
                try await self.performAuth()
                self.authenticated = true
                await self.enterEvenAIMode()
                self.statusMessage = "Reconnected ✨"
            } catch {
                log.error("Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
                self.attemptAutoReconnect(attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        }
    }

    func sendHUDError(_ message: String) {
        Task { if evenAIActive { await sendReply(message) } }
    }
}

// MARK: - CBPeripheralDelegate

extension G2Sniffer: CBPeripheralDelegate {
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
                if char.uuid == G2Constants.charWrite { self.writeChar = char }
                if char.uuid == G2Constants.charNotify {
                    self.notifyChar = char; peripheral.setNotifyValue(true, for: char)
                }
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            if self.writeChar != nil && self.notifyChar != nil {
                self.bleConnected = true
                self.connectContinuation?.resume(); self.connectContinuation = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.logPacket(direction: "RX", data: data)

            // Route TouchBar events through GestureController (Phase 2 state machine)
            if data.count >= 2 && data[0] == G2Constants.TouchBar.command {
                let subcmd = data[1]
                self.gestureController.handleTouchBarEvent(subcmd)
                // Also forward to VCM for legacy compat
                self.voiceCommandManager?.handleTouchBarEvent(subcmd)
            }

            // Route touch service events (0x09-20, 0x08-20) through GestureController
            if data.count >= 8 {
                let svcHi = data[6]; let svcLo = data[7]
                if (svcHi == 0x09 && svcLo == 0x20) || (svcHi == 0x08 && svcLo == 0x20) {
                    if data.count > 10 {
                        let payload = data.subdata(in: 8..<(data.count - 2))
                        if payload.count >= 1 {
                            let eventType = Int(payload[0])
                            self.gestureController.handleEvent(eventType)
                        }
                    }
                }
            }
            self.voiceCommandManager?.handleG2AudioData(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error { log.error("Notify failed for \(characteristic.uuid): \(error.localizedDescription)") }
        }
    }
}

// MARK: - G2BLEManagerDelegate

extension G2Sniffer: G2BLEManagerDelegate {
    nonisolated func bleManager(_ manager: G2BLEManager, didChangeState state: G2BLEManager.State) {}
    nonisolated func bleManager(_ manager: G2BLEManager, didReceiveData data: Data) {
        Task { @MainActor in voiceCommandManager?.handleG2AudioData(data) }
    }
    nonisolated func bleManager(_ manager: G2BLEManager, didDiscoverDevice name: String, rssi: NSNumber) {}
    nonisolated func bleManager(_ manager: G2BLEManager, didReceiveVoiceTranscript text: String, isFinal: Bool) {}
    nonisolated func bleManager(_ manager: G2BLEManager, didReceiveTouchBarEvent subcmd: UInt8) {
        Task { @MainActor in
            voiceCommandManager?.handleTouchBarEvent(subcmd)
            switch subcmd {
            case G2Constants.TouchBar.evenAIStart: micStatus = "🎙️ Aisha listening..."
            case G2Constants.TouchBar.evenAIStop: micStatus = "⏳ Thinking..."
            default: controller.updateMicStatus()
            }
        }
    }
}

// MARK: - AppStateMachineDelegate (Phase 2)

extension G2Sniffer: AppStateMachineDelegate {

    func stateMachine(_ sm: AppStateMachine, didTransitionFrom oldState: AppState, to newState: AppState) {
        NSLog("[Sniffer] App state: \(oldState.rawValue) → \(newState.rawValue)")
    }

    func stateMachineStartMic(_ sm: AppStateMachine) {
        voiceCommandManager?.startListening()
        isListening = true
    }

    func stateMachineStopMic(_ sm: AppStateMachine) {
        voiceCommandManager?.stopListening()
        isListening = false
        audioLevelHistory = Array(repeating: 0, count: 30)
    }

    func stateMachineForceSend(_ sm: AppStateMachine) {
        guard let vcm = voiceCommandManager else { return }
        let transcript = vcm.forceSend()
        isListening = false
        guard !transcript.isEmpty else {
            if sm.inConversation { sm.goConversationReady() } else { sm.goIdle() }
            return
        }
        Task { await sm.processTranscript(transcript) }
    }

    func stateMachine(_ sm: AppStateMachine, showOnHUD text: String) {
        Task {
            if !evenAIActive { await enterEvenAIMode() }
            await sendReply(text)
        }
        lastQuestion = text
    }

    func stateMachine(_ sm: AppStateMachine, showResponseOnHUD text: String) {
        Task {
            if !evenAIActive { await enterEvenAIMode() }
            await sendReply("AISHA: " + text)
        }
        lastAnswer = text
    }

    func stateMachineClearHUD(_ sm: AppStateMachine) {
        Task {
            if evenAIActive {
                await exitEvenAIMode()
                try? await Task.sleep(nanoseconds: 200_000_000)
                await enterEvenAIMode()
            }
        }
        lastAnswer = ""
        lastQuestion = ""
    }

    func stateMachine(_ sm: AppStateMachine, showConversationReadyHUD text: String) {
        Task {
            if !evenAIActive { await enterEvenAIMode() }
            await sendReply(text)
        }
    }

    func stateMachine(_ sm: AppStateMachine, sendToAI transcript: String) async -> String? {
        return await voiceCommandManager?.sendToAI(transcript)
    }
}
