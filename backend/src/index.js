import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import apiRouter from './routes/api.js';

const app = express();
const PORT = Number(process.env.PORT ?? 3001);
const HOST = process.env.HOST ?? '0.0.0.0';

// Behind a reverse proxy (Caddy/nginx/Traefik) we trust the first hop so
// req.ip / secure cookies / rate limits reflect the real client.
app.set('trust proxy', 1);

// CORS_ORIGIN may be a comma-separated list, or "*" to allow any origin.
const rawOrigins = process.env.CORS_ORIGIN ?? 'http://localhost:5173';
const allowedOrigins = rawOrigins.split(',').map((o) => o.trim()).filter(Boolean);
const corsOptions =
  rawOrigins.trim() === '*'
    ? { origin: true }
    : {
        origin(origin, callback) {
          // Allow non-browser clients (no Origin header), e.g. the iOS app.
          if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
          return callback(new Error('Not allowed by CORS'));
        },
      };

app.use(helmet());
app.use(cors(corsOptions));
app.use(express.json({ limit: '16kb' }));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', version: '0.1.0' });
});

app.use('/api', apiRouter);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Central error handler — clean JSON responses, no stack traces leaked.
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err?.message === 'Not allowed by CORS') {
    return res.status(403).json({ error: 'Origin not allowed' });
  }
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, HOST, () => {
  console.log(`Ground to Growth Connect API listening on http://${HOST}:${PORT}`);
});

// Graceful shutdown so containers stop quickly and cleanly.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(`${signal} received, shutting down...`);
    server.close(() => process.exit(0));
  });
}
