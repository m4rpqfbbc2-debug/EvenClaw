// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2PacketBuilder.swift
// Builds BLE packets for the Even G2 protocol including CRC, varint encoding,
// auth handshake, teleprompter content, and display config.

import Foundation

struct G2PacketBuilder {

    // MARK: - CRC-16/CCITT

    /// CRC-16/CCITT (init 0xFFFF, poly 0x1021) over payload bytes only.
    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
                crc &= 0xFFFF
            }
        }
        return crc
    }

    // MARK: - Varint Encoding

    static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var result = Data()
        while v > 0x7F {
            result.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        result.append(UInt8(v & 0x7F))
        return result
    }

    static func encodeVarint(_ value: Int) -> Data {
        encodeVarint(UInt64(value))
    }

    // MARK: - Packet Assembly

    /// Build a complete packet: header(8) + payload + CRC(2).
    /// For single-packet messages (pktTot=1, pktSer=1).
    static func buildPacket(seq: UInt8, serviceHi: UInt8, serviceLo: UInt8, payload: Data) -> Data {
        var packet = Data(capacity: G2Constants.headerSize + payload.count + 2)
        packet.append(G2Constants.magic)
        packet.append(G2Constants.typeCommand)
        packet.append(seq)
        packet.append(UInt8(payload.count + 2)) // len includes CRC
        packet.append(0x01) // pktTot
        packet.append(0x01) // pktSer
        packet.append(serviceHi)
        packet.append(serviceLo)
        packet.append(payload)

        let crc = crc16(payload)
        packet.append(UInt8(crc & 0xFF))       // little-endian
        packet.append(UInt8((crc >> 8) & 0xFF))
        return packet
    }

    /// Build packet for a specific service tuple.
    static func buildPacket(seq: UInt8, service: (UInt8, UInt8), payload: Data) -> Data {
        buildPacket(seq: seq, serviceHi: service.0, serviceLo: service.1, payload: payload)
    }

    /// Build a multi-packet message. Splits payload across packets, each with same seq.
    static func buildMultiPacket(seq: UInt8, service: (UInt8, UInt8), payloads: [Data]) -> [Data] {
        let total = UInt8(payloads.count)
        return payloads.enumerated().map { index, payload in
            var packet = Data()
            packet.append(G2Constants.magic)
            packet.append(G2Constants.typeCommand)
            packet.append(seq)
            packet.append(UInt8(payload.count + 2))
            packet.append(total)
            packet.append(UInt8(index + 1))
            packet.append(service.0)
            packet.append(service.1)
            packet.append(payload)
            let crc = crc16(payload)
            packet.append(UInt8(crc & 0xFF))
            packet.append(UInt8((crc >> 8) & 0xFF))
            return packet
        }
    }

    // MARK: - Authentication (7-packet handshake)

    static func buildAuthSequence() -> [Data] {
        let timestamp = UInt64(Date().timeIntervalSince1970)
        let tsVarint = encodeVarint(timestamp)
        // Transaction ID: -24 encoded as signed varint = 0xE8 FF FF FF FF FF FF FF FF 01
        let txid = Data([0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])

        var packets: [Data] = []

        // Auth 1: Capability query (service 0x80-00)
        packets.append(addCRC(Data([
            0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00,
            0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
        ])))

        // Auth 2: Capability response request (service 0x80-20)
        packets.append(addCRC(Data([
            0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20,
            0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02
        ])))

        // Auth 3: Time sync with transaction ID (service 0x80-20)
        var payload3 = Data([0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08])
        payload3.append(tsVarint)
        payload3.append(0x10)
        payload3.append(txid)
        let len3 = UInt8(payload3.count + 2)
        var pkt3 = Data([0xAA, 0x21, 0x03, len3, 0x01, 0x01, 0x80, 0x20])
        pkt3.append(payload3)
        packets.append(addCRC(pkt3))

        // Auth 4: Additional capability exchange (0x80-00)
        packets.append(addCRC(Data([
            0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00,
            0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
        ])))

        // Auth 5: Additional capability exchange (0x80-00)
        packets.append(addCRC(Data([
            0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00,
            0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
        ])))

        // Auth 6: Final capability (0x80-20)
        packets.append(addCRC(Data([
            0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20,
            0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08, 0x01
        ])))

        // Auth 7: Final time sync (0x80-20)
        var payload7 = Data([0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08])
        payload7.append(tsVarint)
        payload7.append(0x10)
        payload7.append(txid)
        let len7 = UInt8(payload7.count + 2)
        var pkt7 = Data([0xAA, 0x21, 0x07, len7, 0x01, 0x01, 0x80, 0x20])
        pkt7.append(payload7)
        packets.append(addCRC(pkt7))

        return packets
    }

    // MARK: - Display Config (0x0E-20)

    static func buildDisplayConfig(seq: UInt8, msgID: Int) -> Data {
        // Pre-built display config from captured traffic
        let config = Data([
            0x08, 0x01, 0x12, 0x13, 0x08, 0x02, 0x10, 0x90,
            0x4E, 0x1D, 0x00, 0xE0, 0x94, 0x44, 0x25, 0x00,
            0x00, 0x00, 0x00, 0x28, 0x00, 0x30, 0x00, 0x12, 0x13,
            0x08, 0x03, 0x10, 0x0D, 0x0F, 0x1D, 0x00, 0x40,
            0x8D, 0x44, 0x25, 0x00, 0x00, 0x00, 0x00, 0x28,
            0x00, 0x30, 0x00, 0x12, 0x12, 0x08, 0x04, 0x10,
            0x00, 0x1D, 0x00, 0x00, 0x88, 0x42, 0x25,
            0x00, 0x00, 0x00, 0x00, 0x28, 0x00, 0x30,
            0x00, 0x12, 0x12, 0x08, 0x05, 0x10, 0x00, 0x1D,
            0x00, 0x00, 0x92, 0x42, 0x25, 0x00, 0x00,
            0xA2, 0x42, 0x28, 0x00, 0x30, 0x00, 0x12, 0x12,
            0x08, 0x06, 0x10, 0x00, 0x1D, 0x00, 0x00, 0xC6,
            0x42, 0x25, 0x00, 0x00, 0xC4, 0x42, 0x28, 0x00,
            0x30, 0x00, 0x18, 0x00
        ])

        var payload = Data([0x08, 0x02, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(0x22)
        payload.append(UInt8(config.count))
        payload.append(config)
        return buildPacket(seq: seq, service: G2Constants.Service.displayConfig, payload: payload)
    }

    // MARK: - Teleprompter

    /// Type 1: Init teleprompter with scroll mode and content dimensions.
    static func buildTeleprompterInit(seq: UInt8, msgID: Int, totalLines: Int, manualMode: Bool = true) -> Data {
        let mode: UInt8 = manualMode ? 0x00 : 0x01
        let contentHeight = max(1, (totalLines * 2665) / 140)

        var display = Data([0x08, 0x01, 0x10, 0x00, 0x18, 0x00, 0x20, 0x8B, 0x02]) // fixed settings
        display.append(0x28)
        display.append(encodeVarint(contentHeight))
        display.append(contentsOf: [0x30, 0xE6, 0x01]) // line height 230
        display.append(contentsOf: [0x38, 0x8E, 0x0A]) // viewport 1294
        display.append(contentsOf: [0x40, 0x05, 0x48, mode])

        var settings = Data([0x08, 0x01, 0x12, UInt8(display.count)])
        settings.append(display)

        var payload = Data([0x08, 0x01, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(0x1A)
        payload.append(UInt8(settings.count))
        payload.append(settings)

        return buildPacket(seq: seq, service: G2Constants.Service.teleprompter, payload: payload)
    }

    /// Type 3: Content page.
    static func buildContentPage(seq: UInt8, msgID: Int, pageNum: Int, text: String) -> Data {
        let textBytes = Data(("\n" + text).utf8)

        var inner = Data([0x08])
        inner.append(encodeVarint(pageNum))
        inner.append(contentsOf: [0x10, 0x0A]) // 10 lines
        inner.append(0x1A)
        inner.append(encodeVarint(textBytes.count))
        inner.append(textBytes)

        var content = Data([0x2A])
        content.append(encodeVarint(inner.count))
        content.append(inner)

        var payload = Data([0x08, 0x03, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(content)

        return buildPacket(seq: seq, service: G2Constants.Service.teleprompter, payload: payload)
    }

    /// Type 255: Mid-stream marker (required between pages 9 and 10).
    static func buildMarker(seq: UInt8, msgID: Int) -> Data {
        var payload = Data([0x08, 0xFF, 0x01, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(contentsOf: [0x6A, 0x04, 0x08, 0x00, 0x10, 0x06])
        return buildPacket(seq: seq, service: G2Constants.Service.teleprompter, payload: payload)
    }

    /// Type 4: Content complete signal.
    static func buildContentComplete(seq: UInt8, msgID: Int, totalPages: Int, totalLines: Int) -> Data {
        var inner = Data([0x08, 0x00, 0x10])
        inner.append(encodeVarint(totalPages))
        inner.append(0x18)
        inner.append(encodeVarint(totalLines))

        var payload = Data([0x08, 0x04, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(0x32)
        payload.append(encodeVarint(inner.count))
        payload.append(inner)

        return buildPacket(seq: seq, service: G2Constants.Service.teleprompter, payload: payload)
    }

    /// Sync trigger (0x80-00, type 0x0E) — triggers rendering after content send.
    static func buildSync(seq: UInt8, msgID: Int) -> Data {
        var payload = Data([0x08, 0x0E, 0x10])
        payload.append(encodeVarint(msgID))
        payload.append(contentsOf: [0x6A, 0x00])
        return buildPacket(seq: seq, service: G2Constants.Service.authControl, payload: payload)
    }

    // MARK: - Display Wake (0x04-20)

    static func buildDisplayWake(seq: UInt8, msgID: Int) -> Data {
        let payload = Data([0x08, 0x01, 0x10]) + encodeVarint(msgID) + Data([
            0x1A, 0x08, 0x08, 0x01, 0x10, 0x01, 0x18, 0x05, 0x28, 0x01
        ])
        return buildPacket(seq: seq, service: G2Constants.Service.displayWake, payload: payload)
    }

    // MARK: - Helpers

    /// Add CRC to a pre-built packet (payload starts at byte 8).
    private static func addCRC(_ packet: Data) -> Data {
        let payload = packet.subdata(in: G2Constants.headerSize..<packet.count)
        let crc = crc16(payload)
        var result = packet
        result.append(UInt8(crc & 0xFF))
        result.append(UInt8((crc >> 8) & 0xFF))
        return result
    }
}
