# EvenClaw v5 — Clean Build Spec

## Context
This is a clean rewrite of EvenClaw v4, fixing all known bugs from tonight's testing session.
READ THESE FILES BEFORE BUILDING:
- /Users/aishawilliams/.openclaw/workspace/evenclaw-v4-review.md (bug report with exact fixes)
- /Users/aishawilliams/.openclaw/workspace/even-realities-developer-guide.md (SDK reference)

## What WORKS (confirmed on real G2 glasses tonight)
- waitForEvenAppBridge() connects to SDK bridge
- createStartUpPageContainer with 2 TextContainerProperty objects (MUST include borderRdaius: 0)
- textContainerUpgrade to body container for updating display
- bridge.audioControl(true) enables glasses mic
- audioEvent.audioPcm delivers Uint8Array PCM (16kHz S16LE mono)
- Wake word detection via server POST /api/wake-check (Whisper tiny model)
- Full pipeline: wake → record → transcribe → chat → HUD display
- Waveform animation during recording (cycling Unicode bars)
- Typewriter text effect for responses

## BUGS TO FIX (all documented in evenclaw-v4-review.md)

### BUG 1: createStartUpPageContainer — MUST add borderRdaius: 0
```typescript
new TextContainerProperty({
  containerID: 1,
  containerName: 'header',
  xPosition: 0, yPosition: 0, width: 576, height: 32,
  content: 'EVENCLAW',  // SIMPLE ASCII — no Unicode art on create
  isEventCapture: 1,
  borderRdaius: 0,  // REQUIRED — SDK typo, must include
})
```
Use simple ASCII text on create. Send fancy content via textContainerUpgrade AFTER creation succeeds.

### BUG 2: Silence detection — pre-calibrate from wake buffer
- Calculate noise floor from the wake detection buffer BEFORE starting recording
- Set threshold to noiseFloor * 2.5, minimum 30
- Add absolute silence check: if RMS < 30, count as silence regardless
- Max recording time: 15 seconds hard cutoff
- Silence duration: 2 seconds

### BUG 3: Text overflow — show tail only
- MAX_VISIBLE_CHARS = 120 (conservative)
- Only show the last 120 chars of long text
- Don't use contentLength in textContainerUpgrade — let SDK figure it out

### BUG 4 & 5: Tap/double-tap intercepted by Even App
- Don't rely on tap to stop recording — use silence detection + timeout
- Add 30-second auto-dismiss on response
- Still handle events if they come through, but don't depend on them

### BUG 6: Disable HMR
```typescript
// vite.config.ts
server: { hmr: false, host: '0.0.0.0' }
```

### BUG 8: Wake word energy pre-screening
- Before sending audio to Whisper, check RMS of the buffer
- If RMS < 40, skip Whisper (too quiet for speech)
- Increase check interval to 3 seconds

## UX FLOW (from Gregg's feedback)

### 1. Boot
- Show boot screen on HUD for 3 seconds: "▓▓▓ EVENCLAW ▓▓▓ ONLINE"
- Then CLEAR the HUD (empty) — don't leave idle screen permanently showing
- Wake word detection starts silently

### 2. Wake Word Detected → Recording
- HUD shows animated waveform: ▁▃▅▇▅▃▁ cycling
- Says "● REC" and "LISTENING..."
- NO "tap to send" text (doesn't work)
- Recording auto-stops on 2s silence or 15s max

### 3. Processing
- Simple spinner: ◐ ◑ ◒ ◓
- Transcript text types in character by character
- Auto-scrolls — always shows the TAIL of the text (last 120 chars)

### 4. Response
- "── AISHA ──" header
- Text types in at reading speed (~30 chars/sec, teleprompter style)
- Auto-scrolls — always shows the TAIL
- After typing complete, auto-dismiss after 30 seconds
- Double-tap dismisses immediately (if event comes through)

### 5. Back to Idle
- HUD clears
- Wake word detection resumes

## FILE STRUCTURE
```
evenclaw-v5/
  index.html          — browser debug UI (dark, monospace, minimal)
  package.json
  vite.config.ts      — HMR DISABLED
  tsconfig.json
  app.json            — Even Hub manifest
  src/
    main.ts           — browser UI bootstrap
    bridge.ts         — Even Hub SDK connection + HUD rendering (single file, simple)
    audio.ts          — mic capture, silence detection with pre-calibrated noise floor
    wake.ts           — wake word buffer management + energy pre-screening
    hud.ts            — HUD text formatters (boot, listening, processing, response, clear)
    api.ts            — server API calls (wake-check, transcribe, chat, health)
    app.ts            — main orchestrator (state machine, connects everything)
  server/             — ALREADY COPIED from v4
```

## SERVER ENDPOINTS (already built, copy from v4)
- POST /api/wake-check — Whisper tiny, returns {wake, transcript}
- POST /api/transcribe — Whisper base, returns {text}
- POST /api/chat — OpenClaw gateway proxy, returns {response}
- GET /api/health — returns {status: "ok"}

Fix: Move logging middleware BEFORE route handlers in server/index.ts

## CRITICAL IMPLEMENTATION RULES
1. borderRdaius: 0 on ALL TextContainerProperty objects
2. Simple ASCII content on createStartUpPageContainer, fancy content via textContainerUpgrade
3. Check createStartUpPageContainer return value and log it
4. Use bridge.onDeviceStatusChanged to track connection
5. Disable HMR in vite config
6. Pre-calibrate noise floor from wake buffer
7. Energy pre-screen before sending to Whisper (skip if RMS < 40)
8. MAX_VISIBLE_CHARS = 120, show tail of long text
9. Auto-dismiss response after 30 seconds
10. No dependency on tap events — silence + timeout only

## app.json
```json
{
  "package_id": "ai.xgx.evenclaw",
  "edition": "202603",
  "name": "EvenClaw",
  "version": "0.5.0",
  "min_app_version": "0.1.0",
  "tagline": "AI assistant for Even G2",
  "description": "Voice AI assistant for Even Realities G2 smart glasses. Say Hey Aisha to talk.",
  "author": "XGX.ai",
  "entrypoint": "index.html",
  "permissions": { "network": ["*"] }
}
```
