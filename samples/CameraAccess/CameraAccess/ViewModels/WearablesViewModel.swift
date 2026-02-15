// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.

//
// WearablesViewModel.swift
//
// LEGACY FILE — Meta DAT SDK integration disabled for EvenClaw.
// This file is kept for reference but all DAT SDK code is commented out.
// EvenClaw uses GlassesProvider abstraction instead of direct DAT SDK.
//
// The original VisionClaw code managed Meta Ray-Ban device discovery,
// registration, and permissions through the DAT SDK. EvenClaw replaces
// this with the GlassesProvider protocol (see Glasses/ directory).
//

import SwiftUI

// Meta DAT SDK imports — disabled for EvenClaw
// import MWDATCore
// #if canImport(MWDATMockDevice)
// import MWDATMockDevice
// #endif

/// Stub WearablesViewModel for EvenClaw.
/// The real device management is now handled by GlassesProvider implementations.
@MainActor
class WearablesViewModel: ObservableObject {
    @Published var devices: [String] = []
    @Published var hasMockDevice: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var skipToIPhoneMode: Bool = true  // Always iPhone mode for EvenClaw

    func showError(_ error: String) {
        errorMessage = error
        showError = true
    }

    func dismissError() {
        showError = false
    }
}
