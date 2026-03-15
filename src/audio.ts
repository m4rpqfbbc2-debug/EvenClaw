// Mic capture + silence detection with pre-calibrated noise floor
// v5.1: Longer silence threshold (5s), longer max (30s), double-tap to send

type AudioDoneCallback = (pcmData: Uint8Array) => void;
type DebugCallback = (msg: string) => void;

const SILENCE_DURATION_MS = 5000;  // 5 seconds — allows pauses between sentences
const MAX_RECORDING_MS = 30000;    // 30 seconds — room for longer thoughts
const FRAME_DURATION_MS = 10;
const ABSOLUTE_SILENCE_RMS = 30;
const MIN_SPEECH_FRAMES = 30; // 300ms before silence detection kicks in

export class AudioCapture {
  private chunks: Uint8Array[] = [];
  private totalBytes = 0;
  private recording = false;
  private speechFrameCount = 0;
  private silenceFrames = 0;
  private speechDetected = false;
  private noiseFloor = 50;
  private startTime = 0;

  onDone: AudioDoneCallback | null = null;
  onDebug: DebugCallback | null = null;

  get isRecording(): boolean {
    return this.recording;
  }

  setNoiseFloor(rms: number): void {
    this.noiseFloor = Math.max(20, Math.min(rms, 200));
  }

  startRecording(): void {
    this.chunks = [];
    this.totalBytes = 0;
    this.speechFrameCount = 0;
    this.silenceFrames = 0;
    this.speechDetected = false;
    this.recording = true;
    this.startTime = Date.now();
  }

  stopRecording(): Uint8Array {
    this.recording = false;
    return this.getMergedPCM();
  }

  /** Force-send: called when user double-taps to send immediately */
  forceSend(): void {
    if (!this.recording) return;
    this.onDebug?.('Force send (double-tap)');
    this.finalize();
  }

  processAudioFrame(pcmData: Uint8Array): void {
    if (!this.recording) return;

    this.chunks.push(new Uint8Array(pcmData));
    this.totalBytes += pcmData.length;
    this.speechFrameCount++;

    // No max timeout — recording continues until user double-taps to send
    // This prevents accidental auto-sends of background noise

    const rms = computeRMS(pcmData);
    const threshold = this.noiseFloor * 2.5;

    if (this.speechFrameCount % 20 === 0) {
      this.onDebug?.(
        `RMS:${rms.toFixed(0)} floor:${this.noiseFloor.toFixed(0)} thresh:${threshold.toFixed(0)} silence:${this.silenceFrames}`
      );
    }

    if (this.speechFrameCount < MIN_SPEECH_FRAMES) return;

    if (rms < ABSOLUTE_SILENCE_RMS) {
      this.silenceFrames++;
    } else if (rms > threshold) {
      this.speechDetected = true;
      this.silenceFrames = 0;
    } else if (this.speechDetected) {
      this.silenceFrames++;
    }

    // No silence-based auto-send — only double-tap or max timeout sends
    // Silence tracking kept for potential future use
  }

  private finalize(): void {
    if (!this.recording) return;
    this.recording = false;
    const merged = this.getMergedPCM();
    this.onDone?.(merged);
  }

  private getMergedPCM(): Uint8Array {
    const result = new Uint8Array(this.totalBytes);
    let offset = 0;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }
}

export function computeRMS(pcmData: Uint8Array): number {
  if (pcmData.length < 2) return 0;
  const view = new DataView(pcmData.buffer, pcmData.byteOffset, pcmData.byteLength);
  const sampleCount = Math.floor(pcmData.length / 2);
  let sumSquares = 0;
  for (let i = 0; i < sampleCount; i++) {
    const sample = view.getInt16(i * 2, true);
    sumSquares += sample * sample;
  }
  return Math.sqrt(sumSquares / sampleCount);
}
