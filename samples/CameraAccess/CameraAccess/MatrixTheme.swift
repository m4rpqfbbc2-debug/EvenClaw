// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// MatrixTheme.swift
// Central design system — green phosphor / matrix terminal aesthetic.

import SwiftUI

// MARK: - Color Palette

enum MatrixColor {
    /// Primary phosphor green — #00FF41
    static let phosphor = Color(red: 0, green: 1, blue: 0.255)
    /// Dim green for backgrounds — #003B00
    static let darkGreen = Color(red: 0, green: 0.231, blue: 0)
    /// Terminal black — #0D0D0D
    static let terminal = Color(red: 0.051, green: 0.051, blue: 0.051)
    /// Amber accent — #FFB000
    static let amber = Color(red: 1, green: 0.69, blue: 0)
    /// Dim phosphor for secondary text
    static let dimPhosphor = Color(red: 0, green: 0.6, blue: 0.15)
    /// Error red
    static let errorRed = Color(red: 1, green: 0.2, blue: 0.2)
    /// User message color (slightly different green)
    static let userGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
}

// MARK: - Typography

enum MatrixFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let title = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let heading = Font.system(size: 18, weight: .semibold, design: .monospaced)
    static let body = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let micro = Font.system(size: 9, weight: .regular, design: .monospaced)
}

// MARK: - Spacing

enum MatrixSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Glow Effect Modifier

struct PhosphorGlow: ViewModifier {
    var color: Color = MatrixColor.phosphor
    var radius: CGFloat = 8
    var intensity: Double = 0.6

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(intensity), radius: radius / 2, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.5), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func phosphorGlow(color: Color = MatrixColor.phosphor, radius: CGFloat = 8, intensity: Double = 0.6) -> some View {
        modifier(PhosphorGlow(color: color, radius: radius, intensity: intensity))
    }
}

// MARK: - Scanline Overlay

struct ScanlineOverlay: ViewModifier {
    var lineSpacing: CGFloat = 3
    var opacity: Double = 0.04

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                Canvas { ctx, size in
                    for y in stride(from: CGFloat(0), to: size.height, by: lineSpacing) {
                        let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                        ctx.fill(Path(rect), with: .color(.black.opacity(opacity)))
                    }
                }
                .allowsHitTesting(false)
            }
        )
    }
}

extension View {
    func scanlines(spacing: CGFloat = 3, opacity: Double = 0.04) -> some View {
        modifier(ScanlineOverlay(lineSpacing: spacing, opacity: opacity))
    }
}

// MARK: - Matrix Text Style

struct MatrixText: ViewModifier {
    var color: Color = MatrixColor.phosphor
    var glow: Bool = false

    func body(content: Content) -> some View {
        if glow {
            content
                .foregroundStyle(color)
                .phosphorGlow(color: color, radius: 6, intensity: 0.4)
        } else {
            content
                .foregroundStyle(color)
        }
    }
}

extension View {
    func matrixText(color: Color = MatrixColor.phosphor, glow: Bool = false) -> some View {
        modifier(MatrixText(color: color, glow: glow))
    }
}

// MARK: - Terminal Card Background

struct TerminalCard: ViewModifier {
    var borderColor: Color = MatrixColor.darkGreen

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MatrixColor.terminal)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(borderColor.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func terminalCard(border: Color = MatrixColor.darkGreen) -> some View {
        modifier(TerminalCard(borderColor: border))
    }
}

// MARK: - Status Indicator

struct MatrixStatusDot: View {
    let isActive: Bool
    var activeColor: Color = MatrixColor.phosphor
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(isActive ? activeColor : MatrixColor.dimPhosphor.opacity(0.3))
            .frame(width: size, height: size)
            .phosphorGlow(color: activeColor, radius: 4, intensity: isActive ? 0.8 : 0)
    }
}
