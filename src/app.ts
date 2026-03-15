// Main orchestrator — state machine connecting bridge, audio, wake, HUD, API
// v5.1: Conversation mode, no auto-dismiss, double-tap to dismiss + continue

import * as bridge from './bridge.js';
import { AudioCapture } from './audio.js';
import * as hud from './hud.js';
import * as api from './api.js';

export type AppState = 'INIT' | 'IDLE' | 'LISTENING' | 'PROCESSING' | 'RESPONSE' | 'CONVERSATION_READY';

type LogFn = (msg: string, level?: string) => void;

let state: AppState = 'INIT';
let logFn: LogFn = (msg) => console.log(msg);

const audio = new AudioCapture();

// Conversation history for multi-turn chat
const chatHistory: Array<{ role: 'user' | 'assistant'; content: string }> = [];
const MAX_HISTORY = 10;

let inConversation = false;
let animationTimer: ReturnType<typeof setInterval> | null = null;
let animFrame = 0;

const TYPEWRITER_SPEED_MS = 2; // ~500 chars/sec for responses
const TRANSCRIPT_TYPEWRITER_SPEED_MS = 0; // instant for transcript
const BOOT_LINE_DELAY_MS = 600;
const BOOT_HOLD_MS = 2000;
const CONVERSATION_TIMEOUT_MS = 60000;

let conversationTimeoutTimer: ReturnType<typeof setTimeout> | null = null;
let currentResponseText = '';
let responseScrollOffset = 0;

// Response history for scrolling back through previous exchanges
const responseHistory: Array<{ user: string; assistant: string }> = [];
let responseHistoryIndex = -1; // -1 = current response, 0+ = older responses

export function getState(): AppState {
  return state;
}

export function setLogger(fn: LogFn): void {
  logFn = fn;
  bridge.setLogger((msg) => fn(msg, 'info'));
  audio.onDebug = (msg) => fn(msg, 'debug');
}

function setState(newState: AppState): void {
  const prev = state;
  state = newState;
  logFn(`State: ${prev} -> ${newState}`, 'info');
}

function clearTimers(): void {
  if (animationTimer) {
    clearInterval(animationTimer);
    animationTimer = null;
  }
  if (conversationTimeoutTimer) {
    clearTimeout(conversationTimeoutTimer);
    conversationTimeoutTimer = null;
  }
}

// ── Boot sequence ──

export async function init(): Promise<void> {
  setState('INIT');

  const connected = await bridge.initBridge();
  if (!connected) {
    logFn('Failed to connect to glasses bridge', 'error');
    return;
  }

  bridge.setEventCallback(handleEvent);
  bridge.setAudioCallback(handleAudioFrame);

  const hudOk = await bridge.initHUD();
  if (!hudOk) {
    logFn('Failed to create HUD page', 'error');
    return;
  }

  // Scroll in boot screen line by line
  await sleep(500);
  for (let i = 0; i < 5; i++) {
    await bridge.updateHUD(hud.hudBootFrame(i));
    await sleep(BOOT_LINE_DELAY_MS);
  }
  await sleep(BOOT_HOLD_MS);

  await bridge.audioControl(true);
  await goIdle();
}

// ── State transitions ──

async function goIdle(): Promise<void> {
  clearTimers();
  inConversation = false;
  chatHistory.length = 0;
  responseHistory.length = 0;
  responseHistoryIndex = -1;
  setState('IDLE');
  await bridge.updateHUD(' ');           // Clear body
  // Clean HUD — slide forward to activate

  // Disable mic in idle — no wake word polling needed, saves battery
  await bridge.audioControl(false);
  logFn('Idle — look up to activate', 'info');
}

/** After dismissing a response — stay in conversation */
async function goConversationReady(): Promise<void> {
  clearTimers();

  setState('CONVERSATION_READY');
  await clearIdleDot();
  await bridge.updateHUD(hud.hudConversationReady());

  // Disable mic while waiting for gesture
  await bridge.audioControl(false);

  // Timeout: if no interaction for 60s, exit conversation mode
  conversationTimeoutTimer = setTimeout(async () => {
    if (state === 'CONVERSATION_READY') {
      logFn('Conversation timeout (60s) — returning to idle', 'info');
      await goIdle();
    }
  }, CONVERSATION_TIMEOUT_MS);
}

// No-op — header removed, single container now
async function clearIdleDot(): Promise<void> {}

async function startListening(): Promise<void> {
  clearTimers();
  setState('LISTENING');
  await clearIdleDot();

  // Enable mic for recording
  await bridge.audioControl(true);
  await sleep(300); // Brief settle time

  // Set default noise floor (no wake buffer to calibrate from)
  audio.setNoiseFloor(50);

  // Show listening animation
  animFrame = 0;
  await bridge.updateHUD(hud.hudListening(animFrame));
  animationTimer = setInterval(async () => {
    if (state !== 'LISTENING') return;
    animFrame++;
    await bridge.updateHUD(hud.hudListening(animFrame));
  }, 250);

  audio.onDone = handleRecordingDone;
  audio.startRecording();
}

async function handleRecordingDone(pcmData: Uint8Array): Promise<void> {
  clearTimers();
  setState('PROCESSING');
  await clearIdleDot();

  // Show processing spinner
  animFrame = 0;
  await bridge.updateHUD(hud.hudProcessing(animFrame));
  animationTimer = setInterval(async () => {
    if (state !== 'PROCESSING') return;
    animFrame++;
    await bridge.updateHUD(hud.hudProcessing(animFrame));
  }, 200);

  try {
    // Transcribe
    logFn(`Transcribing ${pcmData.length} bytes...`, 'info');
    const transcript = await api.transcribe(pcmData);
    logFn(`Transcript: "${transcript}"`, 'info');

    if (!transcript.trim()) {
      logFn('Empty transcript — returning to conversation or idle', 'warn');
      if (inConversation) {
        await goConversationReady();
      } else {
        await goIdle();
      }
      return;
    }

    // Start AI request immediately (don't wait for typewriter)
    chatHistory.push({ role: 'user', content: transcript });
    if (chatHistory.length > MAX_HISTORY) {
      chatHistory.splice(0, chatHistory.length - MAX_HISTORY);
    }
    logFn('Sending to AI...', 'info');
    const chatPromise = api.chat(transcript, chatHistory);

    // Typewriter the transcript while AI processes (faster speed)
    clearTimers();
    let transcriptChars = 0;
    animFrame = 0;
    while (transcriptChars < transcript.length && state === 'PROCESSING') {
      transcriptChars++;
      animFrame++;
      await bridge.updateHUD(hud.hudProcessingTypewriter(animFrame, transcript, transcriptChars));
      await sleep(TRANSCRIPT_TYPEWRITER_SPEED_MS);
    }

    // Show spinner while waiting for AI to finish
    if (state === 'PROCESSING') {
      animationTimer = setInterval(async () => {
        if (state !== 'PROCESSING') return;
        animFrame++;
        await bridge.updateHUD(hud.hudProcessing(animFrame, transcript));
      }, 200);
    }

    // Wait for AI response
    const response = await chatPromise;
    logFn(`Response (${response.length} chars, state=${state}): "${response.slice(0, 100)}..."`, 'info');

    // Even if state drifted, force show the response — user should always see the answer
    if (!response || response === 'No response from AI.' || response === 'No response received.') {
      logFn('Empty/error response from AI', 'warn');
      await bridge.updateHUD('No response - try again');
      await sleep(2000);
      if (inConversation) {
        await goConversationReady();
      } else {
        await goIdle();
      }
      return;
    }

    // Add response to history
    chatHistory.push({ role: 'assistant', content: response });
    if (chatHistory.length > MAX_HISTORY) {
      chatHistory.splice(0, chatHistory.length - MAX_HISTORY);
    }

    // Save to response history for scroll-back
    responseHistory.push({ user: transcript, assistant: response });
    responseHistoryIndex = -1;

    // Show response with typewriter — force state to RESPONSE regardless
    clearTimers();
    await showResponse(response);
  } catch (err) {
    logFn(`Processing error: ${err}`, 'error');
    await bridge.updateHUD('Error - try again');
    await sleep(2000);
    if (inConversation) {
      await goConversationReady();
    } else {
      await goIdle();
    }
  }
}

async function showResponse(text: string): Promise<void> {
  clearTimers();
  setState('RESPONSE');
  await clearIdleDot();

  currentResponseText = text;
  responseScrollOffset = 0;

  let charsVisible = 0;

  // Typewriter effect
  while (charsVisible < text.length && state === 'RESPONSE') {
    charsVisible++;
    await bridge.updateHUD(hud.hudResponse(text, charsVisible));
    await sleep(TYPEWRITER_SPEED_MS);
  }

  // Show scrollable response — scroll to bottom (where typewriter ended)
  if (state === 'RESPONSE') {
    const totalLines = hud.getResponseLineCount(text);
    responseScrollOffset = Math.max(0, totalLines - 6);
    await bridge.updateHUD(hud.hudResponseScrollable(text, responseScrollOffset));
    logFn(`Response displayed (${totalLines} lines) — scroll arms to review, tap to continue`, 'info');
  }
}

// ── Event handlers ──

function handleEvent(eventType: number): void {
  logFn(`Event: ${eventType} (state: ${state})`, 'debug');

  // ── SLIDE FORWARD / SCROLL UP (1) — primary activation gesture ──

  // Slide forward while IDLE — start recording (new conversation)
  if (eventType === 1 && state === 'IDLE') {
    logFn('Slide forward — starting conversation', 'info');
    inConversation = true;
    startListening();
    return;
  }

  // Slide forward while CONVERSATION_READY — record next message
  if (eventType === 1 && state === 'CONVERSATION_READY') {
    logFn('Slide forward — recording next message', 'info');
    startListening();
    return;
  }

  // Slide forward during response — dismiss and start recording next message
  if (eventType === 1 && state === 'RESPONSE') {
    logFn('Slide forward — recording next message', 'info');
    startListening();
    return;
  }

  // ── SLIDE BACK / SCROLL DOWN (2) — scroll through response history ──

  if (eventType === 2 && state === 'RESPONSE') {
    // First try scrolling within current response
    const maxOffset = Math.max(0, hud.getResponseLineCount(currentResponseText) - 6);
    if (responseScrollOffset > 0) {
      // Scroll up within current response (slide back = go earlier in text)
      responseScrollOffset = Math.max(0, responseScrollOffset - 2);
      bridge.updateHUD(hud.hudResponseScrollable(currentResponseText, responseScrollOffset));
      logFn(`Scroll within response → offset ${responseScrollOffset}`, 'debug');
    } else if (responseHistoryIndex < responseHistory.length - 1) {
      // Already at top of current response — go to previous exchange
      responseHistoryIndex++;
      const prev = responseHistory[responseHistory.length - 1 - responseHistoryIndex];
      currentResponseText = `YOU: ${prev.user}\n\nAISHA: ${prev.assistant}`;
      const totalLines = hud.getResponseLineCount(currentResponseText);
      responseScrollOffset = Math.max(0, totalLines - 6);
      bridge.updateHUD(hud.hudResponseScrollable(currentResponseText, responseScrollOffset));
      logFn(`Previous exchange (${responseHistoryIndex + 1} back)`, 'debug');
    }
    return;
  }

  // ── DOUBLE TAP (3) — send / dismiss ──

  // Double-tap while LISTENING — force send the recording
  if (eventType === 3 && state === 'LISTENING') {
    logFn('Double-tap — sending recording now', 'info');
    audio.forceSend();
    return;
  }

  // Double-tap on response — dismiss and continue conversation
  if (eventType === 3 && state === 'RESPONSE') {
    logFn('Double-tap — dismissing, ready for next message', 'info');
    goConversationReady();
    return;
  }

  // Double-tap during conversation ready — also start recording
  if (eventType === 3 && state === 'CONVERSATION_READY') {
    logFn('Double-tap — recording next message', 'info');
    startListening();
    return;
  }

  // ── SINGLE TAP (0) — dismiss / end ──

  // Single tap on response — dismiss and continue
  if (eventType === 0 && state === 'RESPONSE') {
    logFn('Tap — dismissing, ready for next message', 'info');
    goConversationReady();
    return;
  }

  // Single tap during conversation ready — end conversation, back to dot
  if (eventType === 0 && state === 'CONVERSATION_READY') {
    logFn('Tap — ending conversation, back to idle', 'info');
    goIdle();
    return;
  }
}

function handleAudioFrame(pcm: Uint8Array): void {
  // Mic is only on during LISTENING — all audio goes to recording
  if (state === 'LISTENING') {
    audio.processAudioFrame(pcm);
  }
}

// ── Utilities ──

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
