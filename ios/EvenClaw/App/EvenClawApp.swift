// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClawApp.swift
// @main entry point and scene management.

import SwiftUI

@main
struct EvenClawApp: App {
    @StateObject private var stateMachine = AppStateMachine()
    @AppStorage("onboarding_complete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                stateMachine: stateMachine,
                onboardingComplete: $onboardingComplete
            )
            .preferredColorScheme(.dark)
        }
    }
}
