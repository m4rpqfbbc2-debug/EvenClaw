// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationLogger.swift
// Logs all conversations to local storage for cross-channel context.
// Mirrors the memory logging format from evenclaw-v5/server/chat.ts.

import Foundation
import os.log

private let logr = Logger(subsystem: "ai.xgx.evenclaw", category: "ConversationLog")

struct ConversationEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let userMessage: String
    let aiResponse: String
    let provider: String

    init(userMessage: String, aiResponse: String, provider: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.userMessage = userMessage
        self.aiResponse = aiResponse
        self.provider = provider
    }
}

class ConversationLogger {

    private let fileManager = FileManager.default

    private var logDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ConversationLogs", isDirectory: true)
    }

    init() {
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Log a conversation turn

    func log(userMessage: String, aiResponse: String, provider: String) {
        let entry = ConversationEntry(
            userMessage: userMessage,
            aiResponse: aiResponse,
            provider: provider
        )

        // Append to daily markdown file (mirrors chat.ts format)
        appendToMarkdown(entry)

        // Append to structured JSON log
        appendToJSON(entry)

        logr.info("Logged conversation: \(userMessage.prefix(50)) → \(aiResponse.prefix(50))")
    }

    // MARK: - Markdown Log (mirrors evenclaw-v5/server/chat.ts)

    private func appendToMarkdown(_ entry: ConversationEntry) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayStr = dateFormatter.string(from: entry.timestamp)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: entry.timestamp)

        let mdFile = logDirectory.appendingPathComponent("\(dayStr).md")

        let block = """
        ### EvenClaw [\(timeStr)]
        - **Gregg:** \(entry.userMessage)
        - **Aisha:** \(entry.aiResponse)
        - *Provider: \(entry.provider)*

        """

        appendString(block, to: mdFile)
    }

    // MARK: - JSON Log

    private func appendToJSON(_ entry: ConversationEntry) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayStr = dateFormatter.string(from: entry.timestamp)

        let jsonFile = logDirectory.appendingPathComponent("\(dayStr).json")

        var entries = loadJSONEntries(from: jsonFile)
        entries.append(entry)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: jsonFile, options: .atomic)
        } catch {
            logr.error("Failed to write JSON log: \(error.localizedDescription)")
        }
    }

    private func loadJSONEntries(from url: URL) -> [ConversationEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConversationEntry].self, from: data)) ?? []
    }

    // MARK: - Export

    func exportHistory(days: Int = 7) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var result = "# EvenClaw Conversation History\n\n"

        for dayOffset in (0..<days).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dayStr = dateFormatter.string(from: date)
            let mdFile = logDirectory.appendingPathComponent("\(dayStr).md")

            if let content = try? String(contentsOf: mdFile, encoding: .utf8) {
                result += "## \(dayStr)\n\n"
                result += content
                result += "\n"
            }
        }

        return result
    }

    func exportShareableURL() -> URL? {
        let exportFile = logDirectory.appendingPathComponent("export.md")
        let content = exportHistory()
        do {
            try content.write(to: exportFile, atomically: true, encoding: .utf8)
            return exportFile
        } catch {
            logr.error("Failed to export: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func appendString(_ string: String, to url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = string.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? string.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
