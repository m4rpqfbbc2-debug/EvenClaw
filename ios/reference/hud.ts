// HUD text formatters for Even G2 display (576x288)

const MAX_VISIBLE_CHARS = 120;
const MAX_LINE_WIDTH = 30;

function wrapText(text: string): string {
  const lines: string[] = [];
  for (const rawLine of text.split('\n')) {
    if (rawLine.length <= MAX_LINE_WIDTH) {
      lines.push(rawLine);
    } else {
      let remaining = rawLine;
      while (remaining.length > MAX_LINE_WIDTH) {
        let breakIdx = remaining.lastIndexOf(' ', MAX_LINE_WIDTH);
        if (breakIdx <= 0) breakIdx = MAX_LINE_WIDTH;
        lines.push(remaining.slice(0, breakIdx));
        remaining = remaining.slice(breakIdx).trimStart();
      }
      if (remaining) lines.push(remaining);
    }
  }
  return lines.join('\n');
}

// ── Boot sequence frames (typewriter scroll-in) ──

const BOOT_LINES = [
  'EVENCLAW',
  'v5.1',
  '',
  'by Aisha & Gregg',
  'XGX.ai',
];

/** Boot frames for scroll-in effect — call with increasing frame number */
export function hudBootFrame(frame: number): string {
  const visibleLines = Math.min(frame + 1, BOOT_LINES.length);
  return BOOT_LINES.slice(0, visibleLines).join('\n');
}

export function hudBootComplete(): string {
  return BOOT_LINES.join('\n');
}

// ── Idle — dot is handled by header container, body stays empty ──

export function hudIdle(): string {
  return ' ';
}

// ── Listening / recording ──

const WAVEFORM_FRAMES = [
  '\u2581\u2583\u2585\u2587\u2585\u2583\u2581',
  '\u2583\u2585\u2587\u2585\u2583\u2581\u2583',
  '\u2585\u2587\u2585\u2583\u2581\u2583\u2585',
  '\u2587\u2585\u2583\u2581\u2583\u2585\u2587',
];

export function hudListening(frame: number): string {
  const wave = WAVEFORM_FRAMES[frame % WAVEFORM_FRAMES.length];
  return `\u25CF REC  ${wave}\n\nDOUBLE TAP TO SEND`;
}

// ── Conversation ready — listening without wake word ──

export function hudConversationReady(): string {
  return '\u25B8 SLIDE TO SPEAK\n\nTAP TO END';
}

// ── Processing ──

const SPINNER_FRAMES = ['\u25D0', '\u25D1', '\u25D2', '\u25D3'];

export function hudProcessing(frame: number, transcript?: string): string {
  const spinner = SPINNER_FRAMES[frame % SPINNER_FRAMES.length];
  if (!transcript) {
    return `${spinner}`;
  }
  return wrapText(tailText(`"${transcript}"\n\n${spinner}`));
}

/** Processing with typewriter effect on transcript */
export function hudProcessingTypewriter(frame: number, fullTranscript: string, charsVisible: number): string {
  const visible = fullTranscript.slice(0, charsVisible);
  const cursor = charsVisible < fullTranscript.length ? '\u258C' : '';
  return wrapText(tailText(`"${visible}${cursor}"`));
}

// ── Response ──

/** During typewriter — show tail as it types in */
export function hudResponse(fullText: string, charsVisible: number): string {
  const visible = fullText.slice(0, charsVisible);
  const cursor = charsVisible < fullText.length ? '\u258C' : '';
  const content = `AISHA:\n${visible}${cursor}`;
  return wrapText(tailText(content));
}

/** Scrollable response — offset is character position to start from */
export function hudResponseScrollable(fullText: string, scrollOffset: number): string {
  const tagged = `AISHA:\n${fullText}`;
  const wrapped = wrapText(tagged);
  const lines = wrapped.split('\n');
  const VISIBLE_LINES = 6;
  const startLine = Math.max(0, Math.min(scrollOffset, lines.length - VISIBLE_LINES));
  const visibleLines = lines.slice(startLine, startLine + VISIBLE_LINES);
  
  // Scroll indicator
  let indicator = '';
  if (startLine > 0) indicator += '\u25B2 '; // ▲ can scroll up
  if (startLine + VISIBLE_LINES < lines.length) indicator += '\u25BC'; // ▼ can scroll down
  
  if (indicator) {
    return visibleLines.join('\n') + '\n' + indicator;
  }
  return visibleLines.join('\n');
}

/** Get total lines for scroll bounds */
export function getResponseLineCount(fullText: string): number {
  return wrapText(`AISHA:\n${fullText}`).split('\n').length;
}

// ── Clear ──

export function hudClear(): string {
  return ' ';
}

// ── Helpers ──

function tailText(text: string): string {
  if (text.length <= MAX_VISIBLE_CHARS) return text;
  return text.slice(-MAX_VISIBLE_CHARS);
}

function headText(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return text.slice(0, maxLen - 3) + '...';
}
