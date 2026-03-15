// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// EvenClawApp.swift
// @main entry point and scene management.

import SwiftUI
import CoreBluetooth

/// Triggers Bluetooth permission prompt on app launch.
/// Must be created early so iOS shows the dialog immediately.
class BluetoothPermissionTrigger: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager?
    
    override init() {
        super.init()
        // Creating CBCentralManager triggers the iOS Bluetooth permission dialog
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Just need this to exist — the permission dialog fires on init
    }
}

@main
struct EvenClawApp: App {
    @StateObject private var stateMachine = AppStateMachine()
    @StateObject private var g2Connector = G2AutoConnector()
    @AppStorage("onboarding_complete") private var onboardingComplete = false
    
    // Trigger Bluetooth permission on first launch
    private let bluetoothTrigger = BluetoothPermissionTrigger()

    var body: some Scene {
        WindowGroup {
            ContentView(
                stateMachine: stateMachine,
                g2Connector: g2Connector,
                onboardingComplete: $onboardingComplete
            )
            .preferredColorScheme(.dark)
            .onAppear {
                // Force onboarding to show on fresh installs or after reset
                // Remove this line after testing to keep onboarding persistent
                #if DEBUG
                if !UserDefaults.standard.bool(forKey: "onboarding_shown_v2") {
                    onboardingComplete = false
                    UserDefaults.standard.set(true, forKey: "onboarding_shown_v2")
                }
                #endif
            }
        }
    }
}
