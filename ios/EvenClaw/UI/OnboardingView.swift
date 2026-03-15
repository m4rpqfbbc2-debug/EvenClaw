// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OnboardingView.swift
// 3-screen matrix-style intro: branding with G2, gesture map, BYOK AI.

import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentPage = 0
    @State private var matrixChars: [MatrixChar] = []
    @State private var showContent = false

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            // Matrix rain background on first page
            if currentPage == 0 {
                MatrixRainView(chars: $matrixChars)
                    .ignoresSafeArea()
                    .opacity(0.3)
            }

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    brandingPage.tag(0)
                    gestureMapPage.tag(1)
                    byokPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicators + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Rectangle()
                                .fill(index == currentPage ? MatrixTheme.primary : MatrixTheme.dim)
                                .frame(width: index == currentPage ? 24 : 8, height: 3)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    Button {
                        if currentPage < 2 {
                            withAnimation { currentPage += 1 }
                        } else {
                            isComplete = true
                        }
                    } label: {
                        Text(currentPage < 2 ? "NEXT" : "GET STARTED")
                            .matrixButton()
                    }

                    if currentPage < 2 {
                        Button {
                            isComplete = true
                        } label: {
                            Text("SKIP")
                                .font(MatrixTheme.fontCaption)
                                .foregroundStyle(MatrixTheme.dim)
                        }
                    }
                }
                .padding(.bottom, 48)
            }

            MatrixTheme.ScanlineOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            generateMatrixChars()
            withAnimation(.easeIn(duration: 0.8)) {
                showContent = true
            }
        }
    }

    // MARK: - Page 1: Branding — G2 Hero

    private var brandingPage: some View {
        VStack(spacing: 32) {
            Spacer()

            G2GlassesIcon(size: 80, connected: false)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 1.0).delay(0.2), value: showContent)

            VStack(spacing: 12) {
                PixelRevealText(
                    text: "EVENCLAW",
                    font: MatrixTheme.mono(42, weight: .bold)
                )

                Text("AI ASSISTANT FOR EVEN G2")
                    .font(MatrixTheme.mono(13, weight: .semibold))
                    .foregroundStyle(MatrixTheme.primary.opacity(0.6))
                    .kerning(4)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeIn(duration: 0.8).delay(1.0), value: showContent)
            }

            Text("Voice-controlled. Gesture-driven.\nNo wake word. No cloud lock-in.")
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn(duration: 0.8).delay(1.5), value: showContent)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: Gesture Map — Glasses Arm Diagram

    private var gestureMapPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("CONTROL WITH GESTURES")
                .font(MatrixTheme.fontHeading)
                .foregroundStyle(MatrixTheme.primary)

            // Stylised glasses arm
            VStack(spacing: 0) {
                // Arm visual
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(MatrixTheme.primary.opacity(0.3))
                        .frame(height: 6)
                    Circle()
                        .fill(MatrixTheme.primary)
                        .frame(width: 12, height: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

                Text("G2 ARM TOUCHPAD")
                    .font(MatrixTheme.mono(10))
                    .foregroundStyle(MatrixTheme.dim)
                    .padding(.bottom, 16)

                // Gesture rows
                VStack(alignment: .leading, spacing: 14) {
                    gestureRow(symbol: "\u{2192}", gesture: "SLIDE FORWARD", action: "Record")
                    gestureRow(symbol: "2\u{00D7}", gesture: "TAP", action: "Send")
                    gestureRow(symbol: "\u{2190}", gesture: "SLIDE BACK", action: "Scroll")
                    gestureRow(symbol: "1\u{00D7}", gesture: "TAP", action: "Dismiss")
                }
            }
            .padding(24)
            .background(MatrixTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(MatrixTheme.border, lineWidth: 1)
            )

            Text("Works on G2 arm touchpad.\nPhone mic available as fallback.")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func gestureRow(symbol: String, gesture: String, action: String) -> some View {
        HStack(spacing: 16) {
            Text(symbol)
                .font(MatrixTheme.mono(18, weight: .bold))
                .foregroundStyle(MatrixTheme.primary)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(gesture) = \(action)")
                    .font(MatrixTheme.mono(13, weight: .semibold))
                    .foregroundStyle(MatrixTheme.primary)
            }

            Spacer()
        }
    }

    // MARK: - Page 3: Bring Your Own AI

    private var byokPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(MatrixTheme.primary)
                .shadow(color: MatrixTheme.primary.opacity(0.5), radius: 20)

            Text("BRING YOUR OWN AI")
                .font(MatrixTheme.fontHeading)
                .foregroundStyle(MatrixTheme.primary)

            // Provider icons
            HStack(spacing: 20) {
                providerBadge(icon: "brain", name: "OpenClaw")
                providerBadge(icon: "bubble.left.fill", name: "Anthropic")
                providerBadge(icon: "circle.hexagongrid.fill", name: "OpenAI")
                providerBadge(icon: "sparkles", name: "Gemini")
            }

            VStack(alignment: .leading, spacing: 12) {
                aiOptionRow("OpenClaw", desc: "Local gateway \u{2014} no API key needed")
                aiOptionRow("Claude", desc: "Anthropic API")
                aiOptionRow("GPT", desc: "OpenAI API")
                aiOptionRow("Gemini", desc: "Google API")
                aiOptionRow("Custom", desc: "Any OpenAI-compatible endpoint")
            }
            .padding(20)
            .background(MatrixTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(MatrixTheme.border, lineWidth: 1)
            )

            Text("Bring your own key.\nStored in iOS Keychain \u{2014} never leaves device.")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func providerBadge(icon: String, name: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(MatrixTheme.primary)
                .frame(width: 44, height: 44)
                .overlay(
                    Rectangle()
                        .stroke(MatrixTheme.border, lineWidth: 1)
                )
            Text(name)
                .font(MatrixTheme.mono(8))
                .foregroundStyle(MatrixTheme.dim)
        }
    }

    private func aiOptionRow(_ name: String, desc: String) -> some View {
        HStack {
            Text("\u{25B8}")
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.primary)
            Text(name)
                .font(MatrixTheme.mono(13, weight: .semibold))
                .foregroundStyle(MatrixTheme.primary)
            Text("\u{2014} \(desc)")
                .font(MatrixTheme.fontCaption)
                .foregroundStyle(MatrixTheme.dim)
            Spacer()
        }
    }

    // MARK: - Matrix Rain

    private func generateMatrixChars() {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&"
        matrixChars = (0..<40).map { _ in
            MatrixChar(
                character: String(chars.randomElement()!),
                x: CGFloat.random(in: 0...1),
                speed: Double.random(in: 2...6),
                delay: Double.random(in: 0...3)
            )
        }
    }
}

// MARK: - Matrix Rain Effect

struct MatrixChar: Identifiable {
    let id = UUID()
    let character: String
    let x: CGFloat
    let speed: Double
    let delay: Double
}

struct MatrixRainView: View {
    @Binding var chars: [MatrixChar]

    var body: some View {
        GeometryReader { geo in
            ForEach(chars) { char in
                FallingChar(char: char, height: geo.size.height)
                    .position(x: char.x * geo.size.width, y: 0)
            }
        }
    }
}

private struct FallingChar: View {
    let char: MatrixChar
    let height: CGFloat
    @State private var yOffset: CGFloat = -20

    var body: some View {
        Text(char.character)
            .font(MatrixTheme.mono(12))
            .foregroundStyle(MatrixTheme.primary)
            .offset(y: yOffset)
            .onAppear {
                withAnimation(
                    .linear(duration: char.speed)
                    .delay(char.delay)
                    .repeatForever(autoreverses: false)
                ) {
                    yOffset = height + 20
                }
            }
    }
}
