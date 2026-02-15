// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2Constants.swift
// BLE UUIDs, service IDs, and protocol constants for Even G2 glasses.
// Based on reverse-engineered protocol: github.com/i-soxi/even-g2-protocol

import CoreBluetooth

enum G2Constants {

    // MARK: - BLE UUIDs

    /// Base UUID template: 00002760-08c2-11e1-9073-0e8ac72eXXXX
    static func uuid(_ suffix: UInt16) -> CBUUID {
        CBUUID(string: String(format: "00002760-08c2-11e1-9073-0e8ac72e%04x", suffix))
    }

    /// Main service UUID (suffix 0x0000)
    static let serviceUUID        = uuid(0x0000)
    /// Write characteristic — commands phone→glasses (Write Without Response)
    static let charWrite          = uuid(0x5401)
    /// Notify characteristic — responses glasses→phone
    static let charNotify         = uuid(0x5402)
    /// Service declaration
    static let charServiceDecl    = uuid(0x5450)
    /// Display rendering — 204-byte binary packets
    static let charDisplay        = uuid(0x6402)

    // MARK: - Packet Header

    static let magic: UInt8       = 0xAA
    static let typeCommand: UInt8 = 0x21  // Phone → Glasses
    static let typeResponse: UInt8 = 0x12 // Glasses → Phone
    static let headerSize         = 8

    // MARK: - Service IDs (high, low)

    enum Service {
        static let authControl:    (UInt8, UInt8) = (0x80, 0x00)
        static let authData:       (UInt8, UInt8) = (0x80, 0x20)
        static let authResponse:   (UInt8, UInt8) = (0x80, 0x01)
        static let displayWake:    (UInt8, UInt8) = (0x04, 0x20)
        static let teleprompter:   (UInt8, UInt8) = (0x06, 0x20)
        static let dashboard:      (UInt8, UInt8) = (0x07, 0x20)
        static let deviceInfo:     (UInt8, UInt8) = (0x09, 0x00)
        static let conversate:     (UInt8, UInt8) = (0x0B, 0x20)
        static let tasks:          (UInt8, UInt8) = (0x0C, 0x20)
        static let configuration:  (UInt8, UInt8) = (0x0D, 0x00)
        static let displayConfig:  (UInt8, UInt8) = (0x0E, 0x20)
        static let conversateAlt:  (UInt8, UInt8) = (0x11, 0x20)
        static let commit:         (UInt8, UInt8) = (0x20, 0x20)
        static let displayTrigger: (UInt8, UInt8) = (0x81, 0x20)
    }

    // MARK: - Connection Parameters

    static let mtu = 512
    static let charsPerLine = 25
    static let linesPerPage = 10
    static let minPages = 14
    static let lineHeight: UInt32 = 230
    static let displayWidth: UInt32 = 267
    static let viewportHeight: UInt32 = 1294

    // MARK: - Device Name Pattern

    /// G2 advertises as "Even G2_XX_L_YYYYYY" or "Even G2_XX_R_YYYYYY"
    static func isG2Device(name: String) -> Bool {
        name.hasPrefix("Even G2")
    }

    static func isLeftEar(name: String) -> Bool {
        name.contains("_L_")
    }
}
