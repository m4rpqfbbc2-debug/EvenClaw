// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// G2TextFormatter.swift
// Formats text into pages of wrapped lines for the G2 teleprompter display.
// 25 chars/line, 10 lines/page, minimum 14 pages (pad with spaces).

import Foundation

struct G2TextFormatter {

    static let charsPerLine = G2Constants.charsPerLine  // 25
    static let linesPerPage = G2Constants.linesPerPage  // 10
    static let minPages     = G2Constants.minPages      // 14

    /// Format arbitrary text into teleprompter pages.
    /// Returns array of page strings, each containing 10 newline-separated lines + trailing " \n".
    static func formatText(_ text: String) -> [String] {
        let wrapped = wrapLines(text)

        // Pad to at least linesPerPage lines
        var lines = wrapped
        while lines.count < linesPerPage {
            lines.append(" ")
        }

        // Split into pages of 10 lines each
        var pages: [String] = []
        for i in stride(from: 0, to: lines.count, by: linesPerPage) {
            var pageLines = Array(lines[i..<min(i + linesPerPage, lines.count)])
            while pageLines.count < linesPerPage {
                pageLines.append(" ")
            }
            pages.append(pageLines.joined(separator: "\n") + " \n")
        }

        // Pad to minimum 14 pages
        let emptyPage = Array(repeating: " ", count: linesPerPage).joined(separator: "\n") + " \n"
        while pages.count < minPages {
            pages.append(emptyPage)
        }

        return pages
    }

    /// Word-wrap text to charsPerLine columns.
    static func wrapLines(_ text: String) -> [String] {
        var wrapped: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                wrapped.append("")
                continue
            }

            let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            var current = ""

            for word in words {
                if current.count + word.count + 1 > charsPerLine {
                    if !current.isEmpty {
                        wrapped.append(current.trimmingCharacters(in: .whitespaces))
                    }
                    // Handle words longer than line width
                    if word.count > charsPerLine {
                        var remaining = word
                        while remaining.count > charsPerLine {
                            wrapped.append(String(remaining.prefix(charsPerLine)))
                            remaining = String(remaining.dropFirst(charsPerLine))
                        }
                        current = remaining + " "
                    } else {
                        current = word + " "
                    }
                } else {
                    current += word + " "
                }
            }

            if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                wrapped.append(current.trimmingCharacters(in: .whitespaces))
            }
        }

        if wrapped.isEmpty {
            wrapped.append(" ")
        }

        return wrapped
    }

    /// Calculate total line count (for content height scaling).
    static func lineCount(for text: String) -> Int {
        wrapLines(text).count
    }
}
