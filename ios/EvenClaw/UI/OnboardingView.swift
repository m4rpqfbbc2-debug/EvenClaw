// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// OnboardingView.swift
// 3-screen matrix-style intro sequence.

import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        (
            "eyeglasses",
            "EVENCLAW",
            "AI assistant for your\nEven Realities G2 glasses.\n\nVoice-controlled. Gesture-driven.\nNo wake word needed."
        ),
        (
            "hand.draw",
            "GESTURE CONTROL",
            "SLIDE FORWARD → Start recording\nDOUBLE TAP → Send message\nSLIDE BACK → Scroll history\nTAP → Dismiss / End"
        ),
        (
            "key",
            "BRING YOUR KEY",
            "Connect your own AI provider:\nOpenClaw, Claude, GPT, Gemini,\nor any compatible endpoint.\n\nYour keys stay in iOS Keychain."
        ),
    ]

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        onboardingPage(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicators + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Rectangle()
                                .fill(index == currentPage ? MatrixTheme.primary : MatrixTheme.dim)
                                .frame(width: index == currentPage ? 24 : 8, height: 3)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            isComplete = true
                        }
                    } label: {
                        Text(currentPage < pages.count - 1 ? "NEXT" : "BEGIN")
                            .matrixButton()
                    }

                    if currentPage < pages.count - 1 {
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
        }
    }

    private func onboardingPage(_ page: (icon: String, title: String, body: String)) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 56))
                .foregroundStyle(MatrixTheme.primary)
                .shadow(color: MatrixTheme.primary.opacity(0.5), radius: 20)

            Text(page.title)
                .font(MatrixTheme.fontTitle)
                .foregroundStyle(MatrixTheme.primary)

            Text(page.body)
                .font(MatrixTheme.fontTerminal)
                .foregroundStyle(MatrixTheme.primary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
