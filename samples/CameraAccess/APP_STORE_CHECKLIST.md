# EvenClaw — App Store Submission Checklist

## Privacy Descriptions (Info.plist)

| Key | Status | Description |
|-----|--------|-------------|
| `NSBluetoothAlwaysUsageDescription` | ✅ Done | BLE connection to G2 glasses |
| `NSMicrophoneUsageDescription` | ✅ Done | Voice commands via iPhone mic |
| `NSSpeechRecognitionUsageDescription` | ✅ Done | Speech-to-text for voice input |
| `NSMotionUsageDescription` | ✅ Done | Head gesture detection (CMMotionManager) |
| `NSLocalNetworkUsageDescription` | ✅ Done | OpenClaw gateway on LAN |
| `NSBonjourServices` | ✅ Done | `_http._tcp` for local discovery |

## App Transport Security

| Item | Status | Notes |
|------|--------|-------|
| Remove `NSAllowsArbitraryLoads = true` | ✅ Done | Was too permissive for App Store |
| Keep `NSAllowsLocalNetworking = true` | ✅ Done | Required for LAN gateway access |
| Keep exception for `local` domain | ✅ Done | Allows HTTP to local network hosts |

## Encryption & Export Compliance

| Item | Status | Notes |
|------|--------|-------|
| `ITSAppUsesNonExemptEncryption = NO` | ✅ Done | App uses only standard HTTPS (exempt) |

## Background Modes

| Mode | Status | Purpose |
|------|--------|---------|
| `audio` | ✅ Done | Continuous mic input for wake word detection |
| `bluetooth-central` | ✅ Done | Maintain BLE connection to G2 glasses |

## Required App Store Assets

| Asset | Spec | Status |
|-------|------|--------|
| App Icon | 1024x1024 PNG, no alpha | ⬜ TODO |
| iPhone 6.7" Screenshots | 1290x2796 | ⬜ TODO |
| iPhone 6.5" Screenshots | 1242x2688 | ⬜ TODO |
| iPad Screenshots | 2048x2732 (if supporting iPad) | ⬜ TODO |
| App Preview Video | 15-30s, optional | ⬜ TODO |
| App Description | Max 4000 chars | ⬜ TODO |
| Keywords | Max 100 chars | ⬜ TODO |
| Support URL | Required | ⬜ TODO |
| Privacy Policy URL | Required | ⬜ TODO |
| Category | Utilities / Productivity | ⬜ TODO |

## App Store Connect Configuration

| Item | Status | Notes |
|------|--------|-------|
| Bundle ID: `ai.xgx.evenclaw` | ✅ Set | In project settings |
| Team ID: `U3ZDS3R3ZZ` | ✅ Set | Apple Developer account |
| Version: 2.0 | ✅ Set | `MARKETING_VERSION` in pbxproj |
| Build: 2 | ✅ Set | `CURRENT_PROJECT_VERSION` |
| Deployment Target: iOS 17.0 | ✅ Set | Minimum supported version |
| Signing: Automatic | ✅ Set | Code Sign Style in build settings |

## Pre-Submission Testing

| Test | Status |
|------|--------|
| State machine transitions (IDLE→LISTENING→PROCESSING→RESPONSE) | ⬜ TODO |
| Gesture mapping validation | ⬜ TODO |
| HUD text formatting (truncation, wrapping) | ⬜ TODO |
| BLE disconnection/reconnection recovery | ⬜ TODO |
| Network failure graceful degradation | ⬜ TODO |
| Background audio session persistence | ⬜ TODO |
| Memory leak check (Instruments) | ⬜ TODO |
| Battery impact profiling | ⬜ TODO |
| Test on physical G2 hardware | ⬜ TODO |

## Known Issues to Resolve Before Submission

1. **Hardcoded gateway credentials** — `EvenClawApp.swift` force-sets host/token on launch. Should use Keychain or first-run setup flow.
2. **OpenClaw session key** — Contains phone number in `OpenClawBridge.mergedSessionKey`. Must be configurable or use device-based key.
3. **CameraAccess naming** — Xcode target/bundle still named "CameraAccess" from Meta template. Rename to "EvenClaw" for consistency.
4. **Test target** — Uses Meta `MWDATMockDevice` framework (not available). Replace with EvenClaw-specific tests.
