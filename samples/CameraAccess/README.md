# EvenClaw iOS

AI-powered voice assistant for Even Realities G2 smart glasses.

EvenClaw connects to G2 glasses via BLE, listens for voice commands (wake word, head gestures, or TouchBar), sends them to the OpenClaw AI gateway, and displays responses on the glasses HUD.

## Setup

### Requirements
- Xcode 15+ / iOS 17.0+
- Even Realities G2 glasses (paired via iOS Settings → Bluetooth)
- OpenClaw gateway running on local network

### Build & Run
1. Open `CameraAccess.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a physical iOS device (BLE requires real hardware)

### Configure AI Gateway
On first launch, EvenClaw connects to the OpenClaw gateway at the default address. To change:
1. Tap the gear icon → Settings
2. Update **OpenClaw Gateway** host, port, and token
3. Tap Save

## Architecture

```
EvenClawApp.swift          → App entry point, main UI (SnifferView)
G2Sniffer.swift            → BLE coordinator, packet logging, protocol parsing
├── EvenClawController     → State orchestration (VCM ↔ Sniffer sync)
├── ConversationManager    → Q&A flow, OpenClaw routing, double-tap dismiss
├── ConversationLogger     → Conversation history (markdown + JSON)
└── G2ConnectionManager    → BLE lifecycle, auto-reconnect with backoff

OpenClaw/
├── VoiceCommandManager    → Voice pipeline: wake word → speech → OpenClaw → HUD
├── OpenClawBridge         → HTTP client for OpenClaw gateway
├── WakeWordDetector       → "Hey Aisha" keyword detection
├── WhisperService         → Whisper API integration
└── TTSService             → Text-to-speech output

Glasses/
├── GlassesProvider        → Hardware abstraction protocol
├── EvenG2Provider         → Even G2 implementation
├── HUDFormatter           → Text formatting for HUD display
└── G2Protocol/
    ├── G2BLEManager       → Low-level BLE management
    ├── G2PacketBuilder    → Packet construction (auth, Even AI, teleprompter)
    ├── G2Constants        → UUIDs, service IDs, protocol constants
    ├── G2AudioManager     → G2 mic audio processing
    └── G2TextFormatter    → Text layout for G2 display

Gestures/
└── HeadGestureDetector    → CMMotionManager look-up/look-down detection

Settings/
└── SettingsView           → SwiftUI settings form
```

## How to Connect G2 Glasses

1. Pair your G2 glasses in iOS Settings → Bluetooth
2. Launch EvenClaw — it auto-scans for paired G2 devices
3. Watch the status dots: BLE → Auth → AI should all turn green
4. If disconnected, EvenClaw auto-reconnects with exponential backoff

## Voice Input Methods

| Method | Trigger | Notes |
|--------|---------|-------|
| Wake Word | Say "Hey Aisha" | Always-on background detection |
| Head Gesture | Look up | Uses CMMotionManager or G2 sensors |
| TouchBar | Long-press left temple | G2 hardware trigger |
| Hold Mic | Hold mic button in app | iPhone UI fallback |
| Text Input | Type in text field | Direct text entry |

## Gesture Reference

| Gesture | Action |
|---------|--------|
| Long-press TouchBar | Start voice recording |
| Release TouchBar | Stop recording, send to AI |
| Double-tap TouchBar | Dismiss current response, reset |
| Look up | Start voice recording |
| Look down | Cancel recording |
| Double-tap response (UI) | Dismiss response |

## AI Providers

EvenClaw routes all queries through the **OpenClaw gateway**, which handles:
- Model selection and routing
- Conversation history (cross-channel with WhatsApp)
- Tool calls and agent execution
- Response formatting for HUD display

Configure the gateway connection in Settings. The default token and host are set for local development.

## HUD Display

Responses are displayed on the G2 HUD using the Even AI protocol:
- Short responses (≤60 chars): single frame
- Long responses: streaming chunks with 1.5s reading delay per chunk
- Auto-scroll for multi-page content
- Double-tap to dismiss

## Conversation Logging

All conversations are logged to the app's Documents directory:
- **Markdown**: `ConversationLogs/YYYY-MM-DD.md` — human-readable daily log
- **JSON**: `ConversationLogs/YYYY-MM-DD.json` — structured data for export
- Format mirrors the OpenClaw server's memory logging (`~/.openclaw/workspace/memory/`)

## Contributing

1. Create a feature branch from `evenclawIOS`
2. Follow existing code style (Swift, `@MainActor` for UI state)
3. Do not modify G2 BLE protocol files without testing on real hardware
4. Run tests before submitting: `Cmd+U` in Xcode
5. Keep HUD text under 400 chars for readability
