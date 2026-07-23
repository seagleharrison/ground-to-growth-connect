import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import apiRouter from './routes/api.js';

const app = express();
const PORT = process.env.PORT ?? 3001;

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN ?? 'http://localhost:5173' }));
app.use(express.json({ limit: '16kb' }));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', version: '0.1.0' });
});

app.use('/api', apiRouter);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(PORT, () => {
  console.log(`LocVault API listening on http://localhost:${PORT}`);
});
