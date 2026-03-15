import type { Request, Response } from 'express';
import { execFile } from 'node:child_process';
import { writeFile, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';

function pcmToWav(pcm: Buffer): Buffer {
  const sampleRate = 16000;
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
  const blockAlign = numChannels * (bitsPerSample / 8);
  const dataSize = pcm.length;
  const headerSize = 44;

  const wav = Buffer.alloc(headerSize + dataSize);

  wav.write('RIFF', 0);
  wav.writeUInt32LE(36 + dataSize, 4);
  wav.write('WAVE', 8);
  wav.write('fmt ', 12);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(numChannels, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(byteRate, 28);
  wav.writeUInt16LE(blockAlign, 32);
  wav.writeUInt16LE(bitsPerSample, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(dataSize, 40);
  pcm.copy(wav, headerSize);

  return wav;
}

function runWhisper(wavPath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const outputDir = tmpdir();
    execFile(
      '/opt/homebrew/bin/whisper',
      [
        wavPath,
        '--model', 'base',
        '--language', 'en',
        '--output_format', 'txt',
        '--output_dir', outputDir,
      ],
      { timeout: 15000 },
      async (error, _stdout, stderr) => {
        if (error) {
          console.error('[WakeCheck/Whisper] stderr:', stderr);
          reject(new Error(`Whisper failed: ${error.message}`));
          return;
        }

        const baseName = wavPath.split('/').pop()!.replace('.wav', '');
        const txtPath = join(outputDir, `${baseName}.txt`);

        try {
          const text = await readFile(txtPath, 'utf-8');
          await unlink(txtPath).catch(() => {});
          resolve(text.trim());
        } catch {
          resolve(_stdout?.trim() ?? '');
        }
      }
    );
  });
}

export async function handleWakeCheck(req: Request, res: Response): Promise<void> {
  const id = randomUUID().slice(0, 8);
  const wavPath = join(tmpdir(), `evenclaw-wake-${id}.wav`);

  try {
    const pcmData = req.body as Buffer;
    if (!pcmData || pcmData.length === 0) {
      res.json({ wake: false, transcript: '' });
      return;
    }

    console.log(`[WakeCheck] Received ${pcmData.length} bytes of PCM audio`);

    const wavData = pcmToWav(pcmData);
    await writeFile(wavPath, wavData);

    const transcript = await runWhisper(wavPath);
    // Flexible matching — Whisper often transcribes "hey" as "hi", "hay", "hei" etc.
    const lower = transcript.toLowerCase().replace(/[^a-z\s]/g, '');
    const wake = lower.includes('hey aisha') || 
                 lower.includes('hi aisha') || 
                 lower.includes('hay aisha') ||
                 lower.includes('hei aisha') ||
                 lower.includes('hey asia') ||
                 lower.includes('hi asia') ||
                 lower.includes('hey isha') ||
                 lower.includes('hey aish') ||
                 lower.includes('a aisha') ||
                 lower.includes('aisha') || // Any mention of the name triggers
                 lower.includes('asia');     // Common Whisper mishearing

    console.log(`[WakeCheck] transcript="${transcript}" wake=${wake}`);

    res.json({ wake, transcript });
  } catch (err) {
    console.error('[WakeCheck] Error:', err);
    res.json({ wake: false, transcript: '' });
  } finally {
    await unlink(wavPath).catch(() => {});
  }
}
