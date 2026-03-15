// Even Hub SDK bridge — connection + HUD rendering

import {
  waitForEvenAppBridge,
  CreateStartUpPageContainer,
  TextContainerProperty,
  TextContainerUpgrade,
  OsEventTypeList,
} from '@evenrealities/even_hub_sdk';
import type { EvenAppBridge } from '@evenrealities/even_hub_sdk';

let bridge: EvenAppBridge | null = null;
let hudInitialized = false;
let deviceConnected = false;
let consecutiveHudErrors = 0;
const MAX_HUD_ERRORS = 5;

type LogFn = (msg: string) => void;
let log: LogFn = console.log;

type EventCallback = (eventType: number) => void;
type AudioCallback = (pcm: Uint8Array) => void;

let onEvent: EventCallback | null = null;
let onAudio: AudioCallback | null = null;

export function setLogger(fn: LogFn): void {
  log = fn;
}

export function setEventCallback(cb: EventCallback): void {
  onEvent = cb;
}

export function setAudioCallback(cb: AudioCallback): void {
  onAudio = cb;
}

export function isConnected(): boolean {
  return bridge !== null && hudInitialized;
}

export function isDeviceConnected(): boolean {
  return deviceConnected;
}

/** Initialize bridge with retry */
export async function initBridge(): Promise<boolean> {
  // Reuse existing bridge if available (survives HMR)
  if ((globalThis as Record<string, unknown>).__evenclaw_bridge) {
    bridge = (globalThis as Record<string, unknown>).__evenclaw_bridge as EvenAppBridge;
    log('Reusing existing bridge (HMR)');
    return true;
  }

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      log(`Connecting to glasses (attempt ${attempt}/3)...`);
      bridge = await Promise.race([
        waitForEvenAppBridge(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Bridge timeout')), 10000)
        ),
      ]);

      (globalThis as Record<string, unknown>).__evenclaw_bridge = bridge;
      log('Bridge connected');

      // Listen for device status
      bridge.onDeviceStatusChanged?.((status: { connectType?: string; isConnected?: () => boolean }) => {
        deviceConnected = status.isConnected?.() ?? false;
        log(`Device: ${status.connectType ?? 'unknown'} connected=${deviceConnected}`);
      });

      // Listen for events
      bridge.onEvenHubEvent((event: Record<string, unknown>) => {
        // Audio events
        const audioEvent = event.audioEvent as { audioPcm?: Uint8Array } | undefined;
        if (audioEvent?.audioPcm) {
          onAudio?.(audioEvent.audioPcm);
          return;
        }

        // Input events — check all three sources (text, list, sys)
        const textEvent = event.textEvent as { eventType?: number } | undefined;
        const listEvent = event.listEvent as { eventType?: number } | undefined;
        const sysEvent = event.sysEvent as { eventType?: number } | undefined;

        const et = textEvent?.eventType ?? listEvent?.eventType ?? sysEvent?.eventType;
        if (et !== undefined) {
          onEvent?.(et);
        } else if (textEvent || listEvent || sysEvent) {
          // CLICK_EVENT = 0 normalised to undefined by SDK
          onEvent?.(OsEventTypeList.CLICK_EVENT);
        }
      });

      return true;
    } catch (err) {
      log(`Attempt ${attempt} failed: ${err}`);
      if (attempt === 3) return false;
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  return false;
}

/** Create the initial HUD page — simple ASCII only */
export async function initHUD(): Promise<boolean> {
  if (!bridge) return false;

  // Single full-screen container — no header needed
  const body = new TextContainerProperty({
    containerID: 1,
    containerName: 'body',
    xPosition: 0,
    yPosition: 0,
    width: 576,
    height: 288,
    content: ' ',
    isEventCapture: 1,
    borderRdaius: 0,
  });

  const container = new CreateStartUpPageContainer({
    containerTotalNum: 1,
    textObject: [body],
  });

  const result = await bridge.createStartUpPageContainer(container);
  log(`Page created: ${result}`);

  if (result === 0) {
    hudInitialized = true;
    consecutiveHudErrors = 0;
    return true;
  }

  log(`createStartUpPageContainer failed with code ${result}`);
  return false;
}

/** Update body container text */
export async function updateHUD(text: string): Promise<void> {
  if (!bridge || !hudInitialized) return;

  try {
    await bridge.textContainerUpgrade(
      new TextContainerUpgrade({
        containerID: 1,
        containerName: 'body',
        contentOffset: 0,
        content: text,
      })
    );
    consecutiveHudErrors = 0;
  } catch (err) {
    consecutiveHudErrors++;
    log(`HUD update failed (${consecutiveHudErrors}): ${err}`);
    if (consecutiveHudErrors >= MAX_HUD_ERRORS) {
      log('Too many HUD errors — marking as disconnected');
      hudInitialized = false;
    }
  }
}



/** Enable/disable glasses microphone */
export async function audioControl(enabled: boolean): Promise<void> {
  if (!bridge) return;
  try {
    await bridge.audioControl(enabled);
    log(`Mic ${enabled ? 'enabled' : 'disabled'}`);
  } catch (err) {
    log(`audioControl error: ${err}`);
  }
}
