// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// MatrixTheme.swift
// Green phosphor design system — premium terminal aesthetic for £600 hardware.

import SwiftUI

enum MatrixTheme {

    // MARK: - Colors

    /// Near-black background (#0D0D0D)
    static let background = Color(red: 0.051, green: 0.051, blue: 0.051)

    /// Phosphor green primary (#00FF41)
    static let primary = Color(red: 0, green: 1.0, blue: 0.255)

    /// Dim green for secondary text (#003B00)
    static let dim = Color(red: 0, green: 0.231, blue: 0)

    /// Amber accent (#FFB000)
    static let amber = Color(red: 1.0, green: 0.690, blue: 0)

    /// Error red
    static let error = Color(red: 1.0, green: 0.2, blue: 0.2)

    /// Success green (brighter)
    static let success = Color(red: 0, green: 0.9, blue: 0.3)

    /// Dark surface for cards/sections
    static let surface = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// Border color
    static let border = Color(red: 0, green: 0.4, blue: 0.1)

    // MARK: - Typography

    /// Primary monospace font
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Standard Sizes

    static let fontTitle: Font = mono(28, weight: .bold)
    static let fontHeading: Font = mono(18, weight: .semibold)
    static let fontBody: Font = mono(14)
    static let fontCaption: Font = mono(11)
    static let fontTerminal: Font = mono(13)

    // MARK: - Modifiers

    /// Scanline overlay effect
    struct ScanlineOverlay: View {
        var body: some View {
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: 3) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.black.opacity(0.15)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply matrix terminal styling to a view
    func matrixStyle() -> some View {
        self
            .font(MatrixTheme.fontBody)
            .foregroundStyle(MatrixTheme.primary)
            .background(MatrixTheme.background)
    }

    /// Terminal-style text field
    func matrixTextField() -> some View {
        self
            .font(MatrixTheme.fontBody)
            .foregroundStyle(MatrixTheme.primary)
            .padding(12)
            .background(MatrixTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(MatrixTheme.border, lineWidth: 1)
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    /// Matrix button style
    func matrixButton() -> some View {
        self
            .font(MatrixTheme.mono(14, weight: .semibold))
            .foregroundStyle(MatrixTheme.background)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(MatrixTheme.primary)
    }

    /// Matrix outlined button
    func matrixOutlineButton() -> some View {
        self
            .font(MatrixTheme.mono(14, weight: .semibold))
            .foregroundStyle(MatrixTheme.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .overlay(
                Rectangle()
                    .stroke(MatrixTheme.primary, lineWidth: 1)
            )
    }
}

// MARK: - Animated Glow

struct GlowingText: View {
    let text: String
    let font: Font
    @State private var glowing = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(MatrixTheme.primary)
            .shadow(color: MatrixTheme.primary.opacity(glowing ? 0.8 : 0.3), radius: glowing ? 12 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}
