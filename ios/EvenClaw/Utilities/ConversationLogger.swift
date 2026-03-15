// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

import Foundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "ConvLog")

final class ConversationLogger {

    static let shared = ConversationLogger()

    private let fileManager = FileManager.default
    private let logDirectory: URL

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logDirectory = docs.appendingPathComponent("conversations", isDirectory: true)
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public

    func logExchange(user: String, assistant: String, provider: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = """
        ---
        timestamp: \(timestamp)
        provider: \(provider)
        ---
        USER: \(user)

        AISHA: \(assistant)

        """

        let fileName = dateFileName()
        let fileURL = logDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        log.debug("Logged exchange to \(fileName)")
    }

    func logEvent(_ event: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(event)\n"
        let fileName = dateFileName()
        let fileURL = logDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private

    private func dateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "conversation-\(formatter.string(from: Date())).md"
    }
}
