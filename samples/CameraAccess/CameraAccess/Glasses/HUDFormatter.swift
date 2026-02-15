// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// HUDFormatter.swift
//
// Formats AI responses and tool results for display on a small HUD.
// Smart glasses have extremely limited display real estate (100-200 chars),
// so this formatter strips markdown, extracts key information, and
// truncates intelligently.
//

import Foundation

struct HUDFormatter {

    // MARK: - Configuration

    /// Default character limit for ANCS notification display
    static let notificationLimit = 100

    /// Default character limit for native SDK display
    static let sdkLimit = 200

    // MARK: - Public API

    /// Format an AI text response for HUD display.
    ///
    /// - Parameters:
    ///   - text: Raw AI response text (may contain markdown)
    ///   - maxChars: Maximum characters for the target display
    /// - Returns: Clean, truncated text suitable for HUD
    static func formatResponse(_ text: String, maxChars: Int) -> String {
        var clean = stripMarkdown(text)
        clean = collapseWhitespace(clean)
        clean = truncate(clean, to: maxChars)
        return clean
    }

    /// Format a tool call result for HUD display.
    /// Extracts the key outcome rather than showing raw API response.
    ///
    /// - Parameters:
    ///   - toolName: The tool that was called (e.g. "execute")
    ///   - task: The task description that was sent
    ///   - result: The raw result text from OpenClaw
    ///   - maxChars: Maximum characters for the target display
    /// - Returns: Human-friendly summary of the tool result
    static func formatToolResult(toolName: String, task: String, result: String, maxChars: Int) -> String {
        // Try to extract a concise summary based on the task type
        let summary = extractKeySummary(task: task, result: result)
        return truncate(summary, to: maxChars)
    }

    /// Format for specific content types.
    static func formatWeather(_ text: String, maxChars: Int) -> String {
        // Weather: extract temperature and condition
        // e.g. "Currently 72°F, partly cloudy in San Francisco"
        let clean = stripMarkdown(text)
        return truncate(clean, to: maxChars)
    }

    static func formatCalendar(_ text: String, maxChars: Int) -> String {
        // Calendar: extract next event time and title
        let clean = stripMarkdown(text)
        return truncate(clean, to: maxChars)
    }

    static func formatMessage(_ text: String, maxChars: Int) -> String {
        // Messages: extract sender and preview
        let clean = stripMarkdown(text)
        return truncate(clean, to: maxChars)
    }

    static func formatSearch(_ text: String, maxChars: Int) -> String {
        // Search: extract the key answer, not the full results
        let clean = stripMarkdown(text)
        // Try to get just the first sentence
        if let firstSentence = extractFirstSentence(clean) {
            return truncate(firstSentence, to: maxChars)
        }
        return truncate(clean, to: maxChars)
    }

    // MARK: - Markdown Stripping

    /// Remove common markdown formatting from text.
    static func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove headers (# ## ### etc.)
        result = result.replacingOccurrences(
            of: #"^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )

        // Remove bold (**text** or __text__)
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove italic (*text* or _text_)
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<!\w)_(.+?)_(?!\w)"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove inline code (`text`)
        result = result.replacingOccurrences(
            of: #"`(.+?)`"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove links [text](url) → text
        result = result.replacingOccurrences(
            of: #"\[(.+?)\]\(.+?\)"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove bullet points (- or *)
        result = result.replacingOccurrences(
            of: #"^\s*[-*]\s+"#,
            with: "• ",
            options: [.regularExpression, .anchorsMatchLines]
        )

        // Remove numbered lists (1. 2. etc.)
        result = result.replacingOccurrences(
            of: #"^\s*\d+\.\s+"#,
            with: "",
            options: [.regularExpression, .anchorsMatchLines]
        )

        return result
    }

    // MARK: - Text Processing

    /// Collapse multiple whitespace/newlines into single spaces.
    static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Truncate text to maxChars, adding ellipsis if needed.
    /// Tries to break at word boundary.
    static func truncate(_ text: String, to maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let limit = max(0, maxChars - 1) // Reserve space for "…"
        let prefix = String(text.prefix(limit))

        // Try to break at last space for cleaner truncation
        if let lastSpace = prefix.lastIndex(of: " "),
           prefix.distance(from: prefix.startIndex, to: lastSpace) > limit / 2 {
            return String(prefix[..<lastSpace]) + "…"
        }

        return prefix + "…"
    }

    // MARK: - Key Info Extraction

    /// Try to extract the most important part of a tool result.
    private static func extractKeySummary(task: String, result: String) -> String {
        let taskLower = task.lowercased()
        let clean = stripMarkdown(collapseWhitespace(result))

        // Message sending: look for confirmation
        if taskLower.contains("send") && taskLower.contains("message") {
            if clean.lowercased().contains("sent") {
                return "Message sent ✓"
            }
            return "Done: \(extractFirstSentence(clean) ?? clean)"
        }

        // Adding to list/reminder
        if taskLower.contains("add") || taskLower.contains("remind") {
            if clean.lowercased().contains("added") || clean.lowercased().contains("created") {
                return extractFirstSentence(clean) ?? "Added ✓"
            }
        }

        // Search/lookup
        if taskLower.contains("search") || taskLower.contains("look up") || taskLower.contains("find") {
            return extractFirstSentence(clean) ?? clean
        }

        // Default: first sentence of the result
        return extractFirstSentence(clean) ?? clean
    }

    /// Extract the first sentence from text.
    private static func extractFirstSentence(_ text: String) -> String? {
        // Split on sentence-ending punctuation followed by space or end
        let pattern = #"^(.+?[.!?])(?:\s|$)"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
