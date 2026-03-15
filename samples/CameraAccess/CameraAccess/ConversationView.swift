// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ConversationView.swift
// Terminal-style conversation history with matrix/phosphor aesthetic.

import SwiftUI

// MARK: - Conversation Message Model

struct ConversationMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }

    var timestampString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    var prefix: String {
        switch role {
        case .user: return "YOU >"
        case .assistant: return "AISHA >"
        }
    }

    var color: Color {
        switch role {
        case .user: return MatrixColor.userGreen
        case .assistant: return MatrixColor.phosphor
        }
    }
}

// MARK: - Conversation View

struct ConversationView: View {
    let messages: [ConversationMessage]
    var isTyping: Bool = false
    var typingText: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: MatrixSpacing.md) {
                    ForEach(messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }

                    // Typing indicator
                    if isTyping {
                        TypingIndicator(text: typingText)
                            .id("typing-indicator")
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(.horizontal, MatrixSpacing.md)
                .padding(.vertical, MatrixSpacing.sm)
            }
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
            .onChange(of: typingText) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: MatrixSpacing.xs) {
            // Prefix + timestamp
            HStack(spacing: MatrixSpacing.sm) {
                Text(message.prefix)
                    .font(MatrixFont.caption)
                    .foregroundStyle(message.color)
                    .phosphorGlow(color: message.color, radius: 4, intensity: 0.3)

                Spacer()

                Text(message.timestampString)
                    .font(MatrixFont.micro)
                    .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.5))
            }

            // Message body
            Text(message.text)
                .font(MatrixFont.body)
                .foregroundStyle(message.color.opacity(0.9))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MatrixSpacing.sm + 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(MatrixColor.darkGreen.opacity(message.role == .assistant ? 0.15 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            message.color.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    let text: String
    @State private var dotPhase = 0
    private let dotTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var dots: String {
        String(repeating: ".", count: (dotPhase % 3) + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MatrixSpacing.xs) {
            HStack(spacing: MatrixSpacing.sm) {
                Text("AISHA >")
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.phosphor)
                    .phosphorGlow(color: MatrixColor.phosphor, radius: 4, intensity: 0.3)
                Spacer()
            }

            if text.isEmpty {
                Text("PROCESSING\(dots)")
                    .font(MatrixFont.body)
                    .foregroundStyle(MatrixColor.dimPhosphor)
            } else {
                Text(text)
                    .font(MatrixFont.body)
                    .foregroundStyle(MatrixColor.phosphor.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Blinking cursor
                Rectangle()
                    .fill(MatrixColor.phosphor)
                    .frame(width: 8, height: 14)
                    .opacity(Double(dotPhase % 2))
            }
        }
        .padding(MatrixSpacing.sm + 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(MatrixColor.darkGreen.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(MatrixColor.phosphor.opacity(0.15), lineWidth: 1)
                )
        )
        .onReceive(dotTimer) { _ in dotPhase += 1 }
    }
}
