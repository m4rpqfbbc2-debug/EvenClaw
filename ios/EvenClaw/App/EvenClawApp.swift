// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClawApp.swift
// @main entry point and scene management.

import SwiftUI

@main
struct EvenClawApp: App {
    @StateObject private var stateMachine = AppStateMachine()
    @StateObject private var g2Connector = G2AutoConnector()
    @AppStorage("onboarding_complete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                stateMachine: stateMachine,
                g2Connector: g2Connector,
                onboardingComplete: $onboardingComplete
            )
            .preferredColorScheme(.dark)
        }
    }
}
