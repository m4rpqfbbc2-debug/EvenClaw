// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// HUDFormatter.swift
// Text formatting for Even G2 HUD display (576x288).
// Ported from evenclaw-v5/src/hud.ts — proven formatting patterns.

import Foundation

struct HUDFormatter {

    static let maxVisibleChars = 120
    static let maxLineWidth = 30
    static let visibleLines = 6

    // MARK: - Text Wrapping

    static func wrapText(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.count <= maxLineWidth {
                lines.append(rawLine)
            } else {
                var remaining = rawLine
                while remaining.count > maxLineWidth {
                    var breakIdx = remaining[...remaining.index(remaining.startIndex, offsetBy: min(maxLineWidth, remaining.count - 1))]
                        .lastIndex(of: " ")
                        .map { remaining.distance(from: remaining.startIndex, to: $0) }
                    if breakIdx == nil || breakIdx! <= 0 { breakIdx = maxLineWidth }
                    let idx = remaining.index(remaining.startIndex, offsetBy: breakIdx!)
                    lines.append(String(remaining[..<idx]))
                    remaining = String(remaining[idx...]).trimmingCharacters(in: .whitespaces)
                }
                if !remaining.isEmpty { lines.append(remaining) }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tail Text (show last N chars)

    static func tailText(_ text: String) -> String {
        if text.count <= maxVisibleChars { return text }
        return String(text.suffix(maxVisibleChars))
    }

    // MARK: - Head Text (truncate with ellipsis)

    static func headText(_ text: String, maxLen: Int) -> String {
        if text.count <= maxLen { return text }
        return String(text.prefix(maxLen - 3)) + "..."
    }

    // MARK: - Boot Sequence

    static let bootLines = [
        "EVENCLAW",
        "v5.1",
        "",
        "by Aisha & Gregg",
        "XGX.ai",
    ]

    static func bootFrame(_ frame: Int) -> String {
        let visible = min(frame + 1, bootLines.count)
        return bootLines[0..<visible].joined(separator: "\n")
    }

    static func bootComplete() -> String {
        bootLines.joined(separator: "\n")
    }

    // MARK: - Listening

    static let waveformFrames = [
        "\u{2581}\u{2583}\u{2585}\u{2587}\u{2585}\u{2583}\u{2581}",
        "\u{2583}\u{2585}\u{2587}\u{2585}\u{2583}\u{2581}\u{2583}",
        "\u{2585}\u{2587}\u{2585}\u{2583}\u{2581}\u{2583}\u{2585}",
        "\u{2587}\u{2585}\u{2583}\u{2581}\u{2583}\u{2585}\u{2587}",
    ]

    static func listening(frame: Int) -> String {
        let wave = waveformFrames[frame % waveformFrames.count]
        return "\u{25CF} REC  \(wave)\n\nDOUBLE TAP TO SEND"
    }

    // MARK: - Processing

    static let spinnerFrames = ["\u{25D0}", "\u{25D1}", "\u{25D2}", "\u{25D3}"]

    static func processing(frame: Int, transcript: String? = nil) -> String {
        let spinner = spinnerFrames[frame % spinnerFrames.count]
        guard let transcript, !transcript.isEmpty else { return spinner }
        return wrapText(tailText("\"\(transcript)\"\n\n\(spinner)"))
    }

    // MARK: - Response

    static func response(fullText: String, charsVisible: Int) -> String {
        let visible = String(fullText.prefix(charsVisible))
        let cursor = charsVisible < fullText.count ? "\u{258C}" : ""
        let content = "AISHA:\n\(visible)\(cursor)"
        return wrapText(tailText(content))
    }

    static func responseScrollable(fullText: String, scrollOffset: Int) -> String {
        let tagged = "AISHA:\n\(fullText)"
        let wrapped = wrapText(tagged)
        let lines = wrapped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let startLine = max(0, min(scrollOffset, lines.count - visibleLines))
        let visible = lines[startLine..<min(startLine + visibleLines, lines.count)]

        var indicator = ""
        if startLine > 0 { indicator += "\u{25B2} " }
        if startLine + visibleLines < lines.count { indicator += "\u{25BC}" }

        let result = visible.joined(separator: "\n")
        return indicator.isEmpty ? result : result + "\n" + indicator
    }

    static func responseLineCount(_ fullText: String) -> Int {
        wrapText("AISHA:\n\(fullText)").split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
