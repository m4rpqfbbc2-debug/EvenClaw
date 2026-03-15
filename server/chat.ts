import type { Request, Response } from 'express';
import { appendFile } from 'node:fs/promises';
import { join } from 'node:path';

const DEFAULT_GATEWAY_URL = 'http://127.0.0.1:18789';
const MEMORY_DIR = '/Users/aishawilliams/.openclaw/workspace/memory';

interface ChatRequest {
  message: string;
  history?: Array<{ role: 'user' | 'assistant'; content: string }>;
}

/** Log conversation turn to daily memory file */
async function logToMemory(userMessage: string, aiResponse: string): Promise<void> {
  try {
    const now = new Date();
    const dateStr = now.toISOString().split('T')[0]; // YYYY-MM-DD
    const timeStr = now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/London' });
    const filePath = join(MEMORY_DIR, `${dateStr}.md`);

    const entry = `\n### EvenClaw [${timeStr}]\n- **Gregg:** ${userMessage}\n- **Aisha:** ${aiResponse}\n`;
    await appendFile(filePath, entry, 'utf-8');
    console.log(`[Chat] Logged to ${filePath}`);
  } catch (err) {
    console.error('[Chat] Failed to log to memory:', err);
  }
}

export async function handleChat(req: Request, res: Response): Promise<void> {
  try {
    const { message, history = [] } = req.body as ChatRequest;

    if (!message) {
      res.status(400).json({ error: 'No message provided' });
      return;
    }

    const gatewayUrl = process.env.OPENCLAW_GATEWAY_URL || DEFAULT_GATEWAY_URL;
    const gatewayToken = process.env.OPENCLAW_GATEWAY_TOKEN || '';

    const messages = [
      {
        role: 'system' as const,
        content:
          'You are Aisha, an AI assistant speaking through Even Realities G2 smart glasses to Gregg Curtis, CEO of XGX. ' +
          'Keep responses concise (under 400 characters when possible) since they display on a tiny HUD. ' +
          'Be helpful, direct, and conversational. You know about XGX Group (XGX Ventures, XGX.ai, XDX Dubai), ' +
          'the team (Adam CTO, Luke, Louis, Claire, Levi), current projects (EvenClaw, Pipeforge, SOIBA, Hirestack, DMS), ' +
          'and Gregg\'s business context. This is a voice conversation through smart glasses — be natural.',
      },
      ...history,
      { role: 'user' as const, content: message },
    ];

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (gatewayToken) {
      headers['Authorization'] = `Bearer ${gatewayToken}`;
    }

    const apiRes = await fetch(`${gatewayUrl}/v1/chat/completions`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        messages,
        stream: false,
      }),
    });

    if (!apiRes.ok) {
      const errText = await apiRes.text();
      console.error('[Chat] Gateway error:', apiRes.status, errText);
      res.status(502).json({ error: `Gateway error: ${apiRes.status}` });
      return;
    }

    const data = (await apiRes.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const responseText =
      data.choices?.[0]?.message?.content ?? 'No response from AI.';

    // Log to daily memory file for cross-channel context
    await logToMemory(message, responseText);

    res.json({ response: responseText });
  } catch (err) {
    console.error('[Chat] Error:', err);
    const errMessage = err instanceof Error ? err.message : 'Unknown error';
    res.status(500).json({ error: errMessage });
  }
}
