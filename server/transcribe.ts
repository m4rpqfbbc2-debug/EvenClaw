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
      { timeout: 30000 },
      async (error, _stdout, stderr) => {
        if (error) {
          console.error('[Whisper] stderr:', stderr);
          reject(new Error(`Whisper failed: ${error.message}`));
          return;
        }

        // Whisper outputs <filename>.txt
        const baseName = wavPath.split('/').pop()!.replace('.wav', '');
        const txtPath = join(outputDir, `${baseName}.txt`);

        try {
          const text = await readFile(txtPath, 'utf-8');
          // Clean up txt file
          await unlink(txtPath).catch(() => {});
          resolve(text.trim());
        } catch {
          // Try reading stdout as fallback
          resolve(_stdout?.trim() ?? '');
        }
      }
    );
  });
}

export async function handleTranscribe(req: Request, res: Response): Promise<void> {
  const id = randomUUID().slice(0, 8);
  const wavPath = join(tmpdir(), `evenclaw-${id}.wav`);

  try {
    const pcmData = req.body as Buffer;
    if (!pcmData || pcmData.length === 0) {
      res.status(400).json({ error: 'No audio data received' });
      return;
    }

    console.log(`[Transcribe] Received ${pcmData.length} bytes of PCM audio`);

    const wavData = pcmToWav(pcmData);
    await writeFile(wavPath, wavData);

    const text = await runWhisper(wavPath);
    console.log(`[Transcribe] Result: "${text}"`);

    res.json({ text });
  } catch (err) {
    console.error('[Transcribe] Error:', err);
    const message = err instanceof Error ? err.message : 'Unknown error';
    res.status(500).json({ error: message });
  } finally {
    // Clean up WAV file
    await unlink(wavPath).catch(() => {});
  }
}
