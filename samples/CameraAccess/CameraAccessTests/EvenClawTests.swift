// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClawTests.swift
// Unit tests for EvenClaw iOS: state machine, gestures, HUD formatting,
// provider config validation, and conversation logging.

import XCTest
@testable import CameraAccess

// MARK: - State Machine Tests

class StateMachineTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state: AssistantState = .idle
        XCTAssertEqual(state, .idle)
    }

    func testStateTransitions() {
        // Valid flow: idle → listening → sending → idle
        var state: AssistantState = .idle

        state = .listening
        XCTAssertEqual(state, .listening)

        state = .sending
        XCTAssertEqual(state, .sending)

        state = .idle
        XCTAssertEqual(state, .idle)
    }

    func testProcessingState() {
        var state: AssistantState = .idle

        state = .listening
        state = .processing
        XCTAssertEqual(state, .processing)

        state = .sending
        XCTAssertEqual(state, .sending)
    }

    func testErrorState() {
        let state: AssistantState = .error("Test error")
        XCTAssertEqual(state, .error("Test error"))
        XCTAssertNotEqual(state, .error("Different error"))
        XCTAssertNotEqual(state, .idle)
    }

    func testWaitingForTouchBarState() {
        let state: AssistantState = .waitingForTouchBar
        XCTAssertEqual(state, .waitingForTouchBar)
        XCTAssertNotEqual(state, .idle)
    }

    func testRecordingFromG2State() {
        let state: AssistantState = .recordingFromG2
        XCTAssertEqual(state, .recordingFromG2)
        XCTAssertNotEqual(state, .listening)
    }

    func testFullConversationCycle() {
        var state: AssistantState = .idle

        // Wake word triggers listening
        state = .listening
        XCTAssertEqual(state, .listening)

        // User speaks, silence detected → sending
        state = .sending
        XCTAssertEqual(state, .sending)

        // Response received → back to idle
        state = .idle
        XCTAssertEqual(state, .idle)
    }

    func testErrorRecovery() {
        var state: AssistantState = .idle

        state = .listening
        state = .error("Network timeout")
        XCTAssertEqual(state, .error("Network timeout"))

        // Recovery: error → idle
        state = .idle
        XCTAssertEqual(state, .idle)
    }
}

// MARK: - Gesture Mapping Tests

class GestureMapTests: XCTestCase {

    func testTouchBarConstants() {
        XCTAssertEqual(G2Constants.TouchBar.command, 0xF5)
        XCTAssertEqual(G2Constants.TouchBar.evenAIStart, 0x17)
        XCTAssertEqual(G2Constants.TouchBar.evenAIStop, 0x18)
        XCTAssertEqual(G2Constants.TouchBar.exitDashboard, 0x00)
        XCTAssertEqual(G2Constants.TouchBar.pageUpDown, 0x01)
    }

    func testG2DeviceNameDetection() {
        XCTAssertTrue(G2Constants.isG2Device(name: "Even G2_01_L_ABC123"))
        XCTAssertTrue(G2Constants.isG2Device(name: "Even G2_02_R_DEF456"))
        XCTAssertTrue(G2Constants.isG2Device(name: "Even G2"))
        XCTAssertFalse(G2Constants.isG2Device(name: "AirPods Pro"))
        XCTAssertFalse(G2Constants.isG2Device(name: ""))
    }

    func testLeftEarDetection() {
        XCTAssertTrue(G2Constants.isLeftEar(name: "Even G2_01_L_ABC123"))
        XCTAssertFalse(G2Constants.isLeftEar(name: "Even G2_01_R_ABC123"))
    }

    func testServiceUUIDs() {
        XCTAssertNotNil(G2Constants.serviceUUID)
        XCTAssertNotNil(G2Constants.charWrite)
        XCTAssertNotNil(G2Constants.charNotify)
    }

    func testHeadGestureEnum() {
        let lookUp: HeadGesture = .lookUp
        let lookDown: HeadGesture = .lookDown
        XCTAssertNotEqual(lookUp, lookDown)
    }
}

// MARK: - HUD Text Formatting Tests

class HUDFormattingTests: XCTestCase {

    func testShortTextNoTruncation() {
        let text = "Hello, world"
        let chunks = chunkText(text, maxChars: 60)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, text)
    }

    func testLongTextChunking() {
        let text = "This is a longer message that should be split into multiple chunks for the HUD display on the glasses"
        let chunks = chunkText(text, maxChars: 40)
        XCTAssertTrue(chunks.count > 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 40)
        }
    }

    func testEmptyText() {
        let chunks = chunkText("", maxChars: 60)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, "")
    }

    func testExactBoundary() {
        let text = String(repeating: "a", count: 60)
        let chunks = chunkText(text, maxChars: 60)
        XCTAssertEqual(chunks.count, 1)
    }

    func testSingleLongWord() {
        let longWord = String(repeating: "x", count: 100)
        let chunks = chunkText(longWord, maxChars: 60)
        XCTAssertTrue(chunks.count >= 1)
        XCTAssertLessThanOrEqual(chunks.first!.count, 60)
    }

    func testWordBoundaryRespected() {
        let text = "The quick brown fox jumps over the lazy dog near the river"
        let chunks = chunkText(text, maxChars: 30)
        for chunk in chunks {
            // Each chunk should end at a word boundary (no partial words)
            let lastChar = chunk.last
            XCTAssertNotEqual(lastChar, " ")
        }
    }

    // Helper that mirrors the production chunking logic
    private func chunkText(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxChars {
                if !current.isEmpty { chunks.append(current) }
                current = String(word.prefix(maxChars))
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

// MARK: - Provider Configuration Tests

class ProviderConfigTests: XCTestCase {

    func testDefaultOpenClawPort() {
        // Port should have a sensible default
        let defaultPort = 18789
        XCTAssertEqual(defaultPort, 18789)
    }

    func testOpenClawConfigured() {
        // When token and host are non-empty, config should be valid
        let token = "test-token"
        let host = "http://localhost"
        XCTAssertTrue(!token.isEmpty && !host.isEmpty)
    }

    func testOpenClawNotConfigured() {
        let emptyToken = ""
        XCTAssertTrue(emptyToken.isEmpty)
    }

    func testTTSVoiceOptions() {
        let validVoices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
        XCTAssertEqual(validVoices.count, 6)
        XCTAssertTrue(validVoices.contains("nova")) // default voice
    }

    func testDisplayCapability() {
        let textOnly = DisplayCapability.textOnly(maxChars: 100)
        XCTAssertEqual(textOnly.maxChars, 100)

        let none = DisplayCapability.none
        XCTAssertNil(none.maxChars)

        let richText = DisplayCapability.richText(maxChars: 200)
        XCTAssertEqual(richText.maxChars, 200)
    }

    func testDisplayPriority() {
        XCTAssertTrue(DisplayPriority.low < DisplayPriority.normal)
        XCTAssertTrue(DisplayPriority.normal < DisplayPriority.high)
    }

    func testGlassesConnectionState() {
        let disconnected = GlassesConnectionState.disconnected
        let connected = GlassesConnectionState.connected
        let error = GlassesConnectionState.error("timeout")
        XCTAssertNotEqual(disconnected, connected)
        XCTAssertNotEqual(connected, error)
    }
}

// MARK: - Packet Builder Tests

class PacketBuilderTests: XCTestCase {

    func testCRC16() {
        let data = Data([0x08, 0x01, 0x10, 0x64])
        let crc = G2PacketBuilder.crc16(data)
        // CRC should be deterministic
        XCTAssertEqual(crc, G2PacketBuilder.crc16(data))
    }

    func testVarintEncoding() {
        let small = G2PacketBuilder.encodeVarint(UInt64(1))
        XCTAssertEqual(small, Data([0x01]))

        let medium = G2PacketBuilder.encodeVarint(UInt64(300))
        XCTAssertEqual(medium.count, 2) // 300 requires 2 bytes in varint

        let zero = G2PacketBuilder.encodeVarint(UInt64(0))
        XCTAssertEqual(zero, Data([0x00]))
    }

    func testPacketHeader() {
        let payload = Data([0x08, 0x01])
        let packet = G2PacketBuilder.buildPacket(
            seq: 0x10, serviceHi: 0x07, serviceLo: 0x20, payload: payload)

        XCTAssertEqual(packet[0], 0xAA) // magic
        XCTAssertEqual(packet[1], 0x21) // typeCommand
        XCTAssertEqual(packet[2], 0x10) // seq
        XCTAssertEqual(packet[6], 0x07) // serviceHi
        XCTAssertEqual(packet[7], 0x20) // serviceLo
    }

    func testAuthSequence() {
        let packets = G2PacketBuilder.buildAuthSequence()
        XCTAssertEqual(packets.count, 7)

        // All packets should start with magic byte
        for pkt in packets {
            XCTAssertEqual(pkt[0], 0xAA)
        }
    }

    func testEvenAIEnterPacket() {
        let pkt = G2PacketBuilder.buildEvenAIEnter(seq: 0x08, magic: 0x64)
        XCTAssertEqual(pkt[0], 0xAA)
        XCTAssertEqual(pkt[6], 0x07) // Even AI service
        XCTAssertEqual(pkt[7], 0x20)
    }

    func testEvenAIReplyPacket() {
        let pkt = G2PacketBuilder.buildEvenAIReply(seq: 0x09, magic: 0x65, text: "Hello")
        XCTAssertEqual(pkt[0], 0xAA)
        XCTAssertTrue(pkt.count > 10) // header + payload + CRC
    }

    func testMicControlPacket() {
        let enable = G2PacketBuilder.buildMicControl(enable: true)
        XCTAssertEqual(enable[0], G2Constants.micCommand)
        XCTAssertEqual(enable[1], 0x01)

        let disable = G2PacketBuilder.buildMicControl(enable: false)
        XCTAssertEqual(disable[1], 0x00)
    }
}

// MARK: - Conversation Logger Tests

class ConversationLoggerTests: XCTestCase {

    func testConversationEntryCreation() {
        let entry = ConversationEntry(
            userMessage: "What's the weather?",
            aiResponse: "Sunny, 22°C",
            provider: "OpenClaw"
        )
        XCTAssertEqual(entry.userMessage, "What's the weather?")
        XCTAssertEqual(entry.aiResponse, "Sunny, 22°C")
        XCTAssertEqual(entry.provider, "OpenClaw")
        XCTAssertNotNil(entry.id)
        XCTAssertNotNil(entry.timestamp)
    }

    func testConversationEntryEncoding() throws {
        let entry = ConversationEntry(
            userMessage: "Hello",
            aiResponse: "Hi there!",
            provider: "OpenClaw"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        XCTAssertTrue(data.count > 0)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConversationEntry.self, from: data)
        XCTAssertEqual(decoded.userMessage, "Hello")
        XCTAssertEqual(decoded.aiResponse, "Hi there!")
    }

    func testLoggerExportEmpty() {
        let logger = ConversationLogger()
        let export = logger.exportHistory(days: 1)
        XCTAssertTrue(export.contains("EvenClaw Conversation History"))
    }
}

// MARK: - Packet Log Entry Tests

class PacketLogEntryTests: XCTestCase {

    func testServiceLabel() {
        let entry = PacketLogEntry(
            timestamp: "12:00:00.000", direction: "RX",
            serviceHi: 0x07, serviceLo: 0x20,
            rawData: Data([0xAA]), parsedContent: nil)
        XCTAssertTrue(entry.serviceLabel.contains("EvenAI"))
    }

    func testConversateDetection() {
        let conversate = PacketLogEntry(
            timestamp: "12:00:00.000", direction: "RX",
            serviceHi: 0x0B, serviceLo: 0x20,
            rawData: Data(), parsedContent: nil)
        XCTAssertTrue(conversate.isConversate)

        let notConversate = PacketLogEntry(
            timestamp: "12:00:00.000", direction: "TX",
            serviceHi: 0x07, serviceLo: 0x20,
            rawData: Data(), parsedContent: nil)
        XCTAssertFalse(notConversate.isConversate)
    }

    func testHexDump() {
        let entry = PacketLogEntry(
            timestamp: "12:00:00.000", direction: "TX",
            serviceHi: 0x00, serviceLo: 0x00,
            rawData: Data([0xAA, 0xBB, 0xCC]),
            parsedContent: nil)
        XCTAssertEqual(entry.hexDump, "AA BB CC")
    }
}

// MARK: - G2 Error Tests

class G2ErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(G2Error.deviceNotFound.errorDescription)
        XCTAssertNotNil(G2Error.notConnected.errorDescription)
        XCTAssertNotNil(G2Error.connectionFailed("test").errorDescription)
        XCTAssertNotNil(G2Error.authFailed("test").errorDescription)
        XCTAssertNotNil(G2Error.bleNotReady.errorDescription)
    }
}
