// Server API calls

const SERVER_BASE = '';  // Same origin in dev (Vite proxy) or relative in prod

function apiUrl(path: string): string {
  // If explicitly set (e.g. for testing), use that
  const base = (window as unknown as Record<string, unknown>).__EVENCLAW_API_BASE as string | undefined;
  if (base) return `${base}${path}`;
  // In dev (any local port) or Even Hub WebView — server is on same host, port 3001
  if (location.hostname && location.hostname !== '') {
    return `http://${location.hostname}:3001${path}`;
  }
  return `${SERVER_BASE}${path}`;
}

export async function checkHealth(): Promise<boolean> {
  try {
    const res = await fetch(apiUrl('/api/health'), { signal: AbortSignal.timeout(5000) });
    const data = await res.json() as { status: string };
    return data.status === 'ok';
  } catch {
    return false;
  }
}

export async function wakeCheck(pcmData: Uint8Array): Promise<{ wake: boolean; transcript: string }> {
  const res = await fetch(apiUrl('/api/wake-check'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream' },
    body: pcmData as unknown as BodyInit,
    signal: AbortSignal.timeout(15000),
  });
  return res.json() as Promise<{ wake: boolean; transcript: string }>;
}

export async function transcribe(pcmData: Uint8Array): Promise<string> {
  const res = await fetch(apiUrl('/api/transcribe'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream' },
    body: pcmData as unknown as BodyInit,
    signal: AbortSignal.timeout(30000),
  });
  const data = await res.json() as { text: string };
  return data.text;
}

export async function chat(
  message: string,
  history: Array<{ role: 'user' | 'assistant'; content: string }> = [],
): Promise<string> {
  const res = await fetch(apiUrl('/api/chat'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, history }),
    signal: AbortSignal.timeout(120000), // 2 minutes — tool calls (email etc) can take a while
  });
  if (!res.ok) {
    const errText = await res.text().catch(() => 'unknown');
    throw new Error(`Chat API error ${res.status}: ${errText}`);
  }
  const data = await res.json() as { response: string };
  return data.response || 'No response received.';
}
