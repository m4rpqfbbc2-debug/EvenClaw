// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OnboardingView.swift
// Matrix-style first-launch experience with pixel reveal animations.

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var titleRevealed = false
    @State private var taglineRevealed = false
    @State private var radarAngle: Double = 0
    @State private var scanPulse: CGFloat = 0

    var body: some View {
        ZStack {
            // Background
            MatrixColor.terminal
                .ignoresSafeArea()
                .scanlines(spacing: 2, opacity: 0.06)

            TabView(selection: $currentPage) {
                // Page 1: Title reveal
                titlePage.tag(0)
                // Page 2: Connect G2
                connectPage.tag(1)
                // Page 3: Choose AI
                setupPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Skip button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Text("SKIP >>")
                            .font(MatrixFont.caption)
                            .foregroundStyle(MatrixColor.dimPhosphor)
                    }
                    .padding()
                }
                Spacer()
            }

            // Page indicator
            VStack {
                Spacer()
                HStack(spacing: MatrixSpacing.sm) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(i == currentPage ? MatrixColor.phosphor : MatrixColor.darkGreen)
                            .frame(width: i == currentPage ? 24 : 8, height: 3)
                            .phosphorGlow(color: MatrixColor.phosphor, radius: 4, intensity: i == currentPage ? 0.6 : 0)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Page 1: Title

    private var titlePage: some View {
        VStack(spacing: MatrixSpacing.lg) {
            Spacer()

            // Title with pixel-by-pixel reveal
            Text("EVENCLAW")
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .foregroundStyle(MatrixColor.phosphor)
                .phosphorGlow(color: MatrixColor.phosphor, radius: 12, intensity: 0.7)
                .opacity(titleRevealed ? 1 : 0)
                .scaleEffect(titleRevealed ? 1 : 0.8)

            if taglineRevealed {
                VStack(spacing: MatrixSpacing.sm) {
                    Text("AI-POWERED SMART GLASSES")
                        .font(MatrixFont.caption)
                        .foregroundStyle(MatrixColor.dimPhosphor)
                        .tracking(3)

                    Text("XGX.ai")
                        .font(MatrixFont.body)
                        .foregroundStyle(MatrixColor.amber)
                        .phosphorGlow(color: MatrixColor.amber, radius: 6, intensity: 0.4)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            // Next prompt
            Text("SWIPE TO CONTINUE")
                .font(MatrixFont.micro)
                .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.5))
                .opacity(taglineRevealed ? 1 : 0)
                .padding(.bottom, 60)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                titleRevealed = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(1.2)) {
                taglineRevealed = true
            }
        }
    }

    // MARK: - Page 2: Connect G2

    private var connectPage: some View {
        VStack(spacing: MatrixSpacing.xl) {
            Spacer()

            Text("CONNECT YOUR G2")
                .font(MatrixFont.heading)
                .foregroundStyle(MatrixColor.phosphor)
                .phosphorGlow(color: MatrixColor.phosphor, radius: 8, intensity: 0.5)

            // Radar sweep animation
            ZStack {
                // Concentric rings
                ForEach(1..<4, id: \.self) { ring in
                    Circle()
                        .strokeBorder(MatrixColor.phosphor.opacity(0.1 + Double(ring) * 0.05), lineWidth: 1)
                        .frame(width: CGFloat(ring) * 60, height: CGFloat(ring) * 60)
                }

                // Sweep line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [MatrixColor.phosphor.opacity(0.6), .clear],
                            startPoint: .center,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 90, height: 2)
                    .offset(x: 45)
                    .rotationEffect(.degrees(radarAngle))

                // Scan pulse
                Circle()
                    .fill(MatrixColor.phosphor.opacity(0.15))
                    .frame(width: 180 * scanPulse, height: 180 * scanPulse)
                    .opacity(Double(1 - scanPulse))

                // Center dot
                Circle()
                    .fill(MatrixColor.phosphor)
                    .frame(width: 8, height: 8)
                    .phosphorGlow(color: MatrixColor.phosphor, radius: 6, intensity: 0.8)
            }
            .frame(width: 200, height: 200)

            VStack(spacing: MatrixSpacing.sm) {
                Text("BLUETOOTH SCANNING")
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.dimPhosphor)
                    .tracking(2)

                Text("Pair your Even G2 glasses\nin iOS Settings first")
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.dimPhosphor.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                radarAngle = 360
            }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                scanPulse = 1
            }
        }
    }

    // MARK: - Page 3: Choose AI

    private var setupPage: some View {
        VStack(spacing: MatrixSpacing.xl) {
            Spacer()

            Text("CHOOSE YOUR AI")
                .font(MatrixFont.heading)
                .foregroundStyle(MatrixColor.phosphor)
                .phosphorGlow(color: MatrixColor.phosphor, radius: 8, intensity: 0.5)

            VStack(spacing: MatrixSpacing.md) {
                Text("EvenClaw routes your voice\nthrough OpenClaw gateway\nto any AI provider")
                    .font(MatrixFont.body)
                    .foregroundStyle(MatrixColor.dimPhosphor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Text("Configure in Settings")
                    .font(MatrixFont.caption)
                    .foregroundStyle(MatrixColor.amber)
            }

            Spacer()

            Button {
                onComplete()
            } label: {
                Text("[ ENTER ]")
                    .font(MatrixFont.heading)
                    .foregroundStyle(MatrixColor.phosphor)
                    .phosphorGlow(color: MatrixColor.phosphor, radius: 10, intensity: 0.6)
                    .padding(.horizontal, MatrixSpacing.xl)
                    .padding(.vertical, MatrixSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(MatrixColor.phosphor.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.bottom, 60)
        }
    }
}
