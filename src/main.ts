// Browser UI bootstrap — debug panel for EvenClaw v5

import * as app from './app.js';

const dotEl = document.getElementById('dot')!;
const statusTextEl = document.getElementById('status-text')!;
const logEl = document.getElementById('log')!;

function setStatus(text: string, color: 'green' | 'red' | 'yellow'): void {
  statusTextEl.textContent = text;
  dotEl.className = `dot ${color}`;
}

function appendLog(msg: string, level: string = 'info'): void {
  const time = new Date().toLocaleTimeString();
  const line = document.createElement('div');
  line.className = level;
  line.textContent = `[${time}] ${msg}`;
  logEl.appendChild(line);
  logEl.scrollTop = logEl.scrollHeight;

  // Keep log size manageable
  while (logEl.childElementCount > 500) {
    logEl.removeChild(logEl.firstChild!);
  }
}

// Wire up logger
app.setLogger((msg: string, level?: string) => {
  appendLog(msg, level ?? 'info');

  // Update status display based on state
  const state = app.getState();
  switch (state) {
    case 'INIT':
      setStatus('Initializing...', 'yellow');
      break;
    case 'IDLE':
      setStatus('Idle — listening for wake word', 'green');
      break;
    case 'LISTENING':
      setStatus('Recording...', 'yellow');
      break;
    case 'PROCESSING':
      setStatus('Processing...', 'yellow');
      break;
    case 'RESPONSE':
      setStatus('Showing response', 'green');
      break;
  }
});

// Start the app
setStatus('Starting...', 'yellow');
appendLog('EvenClaw v5 starting...', 'info');

app.init().catch((err) => {
  appendLog(`Fatal error: ${err}`, 'error');
  setStatus('Error', 'red');
});
