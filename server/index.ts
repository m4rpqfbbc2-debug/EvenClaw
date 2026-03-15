import express from 'express';
import cors from 'cors';
import { handleTranscribe } from './transcribe.js';
import { handleChat } from './chat.js';
import { handleWakeCheck } from './wake-check.js';

const app = express();
const PORT = parseInt(process.env.PORT || '3001', 10);

app.use(cors());

// Log all requests for monitoring — BEFORE routes so it fires for matched routes
app.use((req, _res, next) => {
  console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${req.path}`);
  next();
});

app.use('/api/chat', express.json({ limit: '1mb' }));

// Raw body for PCM audio
app.use('/api/transcribe', express.raw({ type: 'application/octet-stream', limit: '10mb' }));
app.use('/api/wake-check', express.raw({ type: 'application/octet-stream', limit: '1mb' }));

app.post('/api/transcribe', handleTranscribe);
app.post('/api/chat', handleChat);
app.post('/api/wake-check', handleWakeCheck);

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`[EvenClaw Server] listening on :${PORT}`);
});
