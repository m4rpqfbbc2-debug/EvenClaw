// Wake word buffer management + energy pre-screening

import { computeRMS } from './audio.js';

const WAKE_BUFFER_DURATION_MS = 3000;
const SAMPLE_RATE = 16000;
const BYTES_PER_SAMPLE = 2;
const MAX_BUFFER_BYTES = SAMPLE_RATE * BYTES_PER_SAMPLE * (WAKE_BUFFER_DURATION_MS / 1000); // 96000
const ENERGY_THRESHOLD = 40; // Min RMS to bother sending to Whisper

export class WakeBuffer {
  private chunks: Uint8Array[] = [];
  private totalBytes = 0;

  /** Add audio frame to rolling buffer */
  addFrame(pcmData: Uint8Array): void {
    this.chunks.push(new Uint8Array(pcmData));
    this.totalBytes += pcmData.length;

    // Trim old data to stay within buffer duration
    while (this.totalBytes > MAX_BUFFER_BYTES && this.chunks.length > 1) {
      const removed = this.chunks.shift()!;
      this.totalBytes -= removed.length;
    }
  }

  /** Get current buffer size in bytes */
  get byteLength(): number {
    return this.totalBytes;
  }

  /** Get merged buffer data */
  getData(): Uint8Array {
    const result = new Uint8Array(this.totalBytes);
    let offset = 0;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }

  /** Energy pre-screen: check if buffer has enough energy for speech */
  hasEnoughEnergy(): boolean {
    if (this.totalBytes < 16000) return false; // Less than 0.5s of audio
    const data = this.getData();
    const rms = computeRMS(data);
    return rms >= ENERGY_THRESHOLD;
  }

  /** Calculate noise floor from first portion of buffer (for silence detection calibration) */
  calculateNoiseFloor(): number {
    if (this.totalBytes < 3200) return 50; // Need at least 100ms
    const data = this.getData();
    // Use first 1 second (32000 bytes) for calibration
    const calibrationBytes = Math.min(32000, data.length);
    const calibrationData = data.slice(0, calibrationBytes);
    return computeRMS(calibrationData);
  }

  /** Clear the buffer */
  clear(): void {
    this.chunks = [];
    this.totalBytes = 0;
  }
}
