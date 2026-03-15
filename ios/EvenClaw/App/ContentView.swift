// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ContentView.swift
// Root view coordinator — routes between onboarding, setup, and main view.

import SwiftUI

struct ContentView: View {
    @ObservedObject var stateMachine: AppStateMachine
    @Binding var onboardingComplete: Bool
    @State private var needsSetup: Bool = false

    var body: some View {
        ZStack {
            MatrixTheme.background.ignoresSafeArea()

            if !onboardingComplete {
                OnboardingView(isComplete: $onboardingComplete)
                    .transition(.opacity)
            } else if needsSetup {
                SetupView { provider in
                    if let provider {
                        stateMachine.setAIProvider(provider)
                        needsSetup = false
                    }
                }
                .transition(.move(edge: .trailing))
            } else {
                MainView(stateMachine: stateMachine)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingComplete)
        .animation(.easeInOut(duration: 0.3), value: needsSetup)
        .onAppear {
            loadSavedProvider()
        }
        .onChange(of: onboardingComplete) { _, complete in
            if complete {
                checkNeedsSetup()
            }
        }
    }

    private func loadSavedProvider() {
        guard let savedType = KeychainManager.load(.selectedProvider),
              let type = AIProviderType(rawValue: savedType) else {
            if onboardingComplete { needsSetup = true }
            return
        }

        let provider: (any AIProvider)? = switch type {
        case .openClaw: OpenClawProvider()
        case .anthropic: AnthropicProvider()
        case .openAI: OpenAIProvider()
        case .gemini: GeminiProvider()
        case .custom: CustomProvider()
        }

        if let provider {
            stateMachine.setAIProvider(provider)
        } else if onboardingComplete {
            needsSetup = true
        }
    }

    private func checkNeedsSetup() {
        if KeychainManager.load(.selectedProvider) == nil {
            needsSetup = true
        }
    }
}
