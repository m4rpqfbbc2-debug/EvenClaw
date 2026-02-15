# EvenClaw 🦅👓

**AI Assistant for Even Realities G2 Smart Glasses + OpenClaw**

EvenClaw turns Even Realities G2 smart glasses into an AI-powered heads-up assistant. It combines Google Gemini's multimodal AI (voice + vision) with OpenClaw's agentic tool execution, displaying results on the G2's micro-LED HUD.

> Forked from [VisionClaw](https://github.com/sseanliu/VisionClaw) (Meta Ray-Ban integration) by XGX.ai

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    iPhone App                        │
│                                                      │
│  ┌──────────┐   ┌────────────────┐   ┌───────────┐ │
│  │  iPhone   │──▶│ AISessionMgr   │──▶│  Gemini   │ │
│  │  Camera   │   │                │   │  Live API  │ │
│  │ (vision)  │   │  Orchestrates  │◀──│ (WebSocket)│ │
│  └──────────┘   │  full pipeline │   └───────────┘ │
│                  │                │                   │
│  ┌──────────┐   │                │   ┌───────────┐ │
│  │  iPhone   │──▶│                │──▶│ OpenClaw  │ │
│  │   Mic     │   │                │   │  Gateway  │ │
│  │ (voice)   │   │                │◀──│ (tools)   │ │
│  └──────────┘   └───────┬────────┘   └───────────┘ │
│                          │                           │
│                          ▼                           │
│                 ┌────────────────┐                   │
│                 │ GlassesProvider│                   │
│                 │  (abstraction) │                   │
│                 └───────┬────────┘                   │
│                         │                            │
│            ┌────────────┼────────────┐              │
│            ▼            ▼            ▼              │
│     ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│     │Notif.    │ │ EvenG2   │ │PhoneOnly │        │
│     │Provider  │ │ Provider │ │ Provider │        │
│     │(ANCS)    │ │(SDK stub)│ │(fallback)│        │
│     └────┬─────┘ └──────────┘ └──────────┘        │
│          │                                          │
└──────────┼──────────────────────────────────────────┘
           │ iOS Notification (ANCS)
           ▼
    ┌──────────────┐
    │  Even G2     │
    │  HUD Display │
    │  👓          │
    └──────────────┘
```

## How It Works

1. **Voice Input** → iPhone mic captures speech → sent to Gemini Live API
2. **Vision** → iPhone back camera captures frames (~1fps) → sent to Gemini
3. **AI Processing** → Gemini processes voice + vision, generates response
4. **Tool Execution** → If action needed, Gemini calls `execute` → OpenClaw handles it
5. **Audio Output** → Gemini speaks the response through iPhone speaker
6. **HUD Display** → Key text is pushed to G2 via iOS notifications (ANCS)

## Hardware Abstraction

EvenClaw uses a `GlassesProvider` protocol to abstract over different glasses hardware:

| Provider | Display | Audio | Camera | Status |
|----------|---------|-------|--------|--------|
| `NotificationProvider` | ANCS notifications (100 chars) | Phone | Phone | ✅ Working |
| `PhoneOnlyProvider` | None (audio only) | Phone | Phone | ✅ Working |
| `EvenG2Provider` | SDK HUD (200 chars) | Glasses | Phone | 🔜 Pending SDK |

## Setup

### Prerequisites
- iOS 17.0+, Xcode 15+
- Google Gemini API key ([get one](https://aistudio.google.com/apikey))
- OpenClaw gateway running on your Mac
- Even Realities G2 glasses (optional — works without them)

### Build
1. Clone this repo
2. Copy `Secrets.swift.example` → `Secrets.swift` and add your API keys
3. Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode
4. Build and run on your iPhone

### Configure
- Gemini API key, OpenClaw host/port are configurable in Settings
- Glasses provider is set in `CameraAccessApp.swift` (change the initializer)

## Current Status

- ✅ iPhone camera → Gemini vision pipeline
- ✅ Voice conversation via Gemini Live
- ✅ Tool calling via OpenClaw
- ✅ Notification-based HUD display (ANCS)
- ✅ HUD text formatting (markdown stripping, truncation)
- ✅ Hardware abstraction layer
- 🔜 Even G2 native SDK integration (pending pilot program)
- 🔜 G2 audio routing (mic/speakers through glasses)
- 🔜 G2 touch gesture input

## Project Structure

```
samples/CameraAccess/CameraAccess/
├── Glasses/                    # NEW — Hardware abstraction layer
│   ├── GlassesProvider.swift   # Protocol + capability enums
│   ├── AISessionManager.swift  # Full pipeline orchestrator
│   ├── HUDFormatter.swift      # Display text formatting
│   ├── NotificationBridge.swift # iOS notification wrapper
│   ├── NotificationProvider.swift # ANCS-based glasses provider
│   ├── PhoneOnlyProvider.swift # No-glasses fallback
│   └── EvenG2Provider.swift    # Even SDK stub (future)
├── Gemini/                     # Gemini Live API integration
├── OpenClaw/                   # OpenClaw tool calling bridge
├── iPhone/                     # iPhone camera manager
├── WebRTC/                     # Live streaming (kept from VisionClaw)
├── Settings/                   # User preferences
└── Views/                      # SwiftUI interface
```

## Credits

- **VisionClaw** by [sseanliu](https://github.com/sseanliu/VisionClaw) — the original Meta Ray-Ban + Gemini integration
- **OpenClaw** — agentic tool execution gateway
- **XGX.ai** — EvenClaw development

## License

See [LICENSE](LICENSE) for the original VisionClaw license terms.
