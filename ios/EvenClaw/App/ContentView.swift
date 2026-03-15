// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// ContentView.swift
// Root view coordinator — routes between onboarding, setup, and main view.
// NEVER blocks on G2 connection. G2 scanning starts after setup completes.

import SwiftUI

struct ContentView: View {
    @ObservedObject var stateMachine: AppStateMachine
    @ObservedObject var g2Connector: G2AutoConnector
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
                        // Start G2 scanning in background after AI is configured
                        g2Connector.startScanning()
                    }
                }
                .transition(.move(edge: .trailing))
            } else {
                MainView(stateMachine: stateMachine, g2Connector: g2Connector)
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
        .onChange(of: g2Connector.scanState) { _, newState in
            if case .connected = newState {
                stateMachine.glassesAvailable = true
                stateMachine.glasses = g2Connector.glassesProvider
            } else if g2Connector.glassesProvider == nil {
                stateMachine.glassesAvailable = false
                stateMachine.glasses = nil
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
            // Start G2 scanning since we have a saved provider
            g2Connector.startScanning()
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
