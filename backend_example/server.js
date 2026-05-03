/**
 * Backend de exemplo para receber métricas do EMetrics IoT
 *
 * Uso:
 *   npm install
 *   node server.js
 *
 * Endpoints:
 *   POST /metrics   - Recebe uma métrica do app (Bearer token obrigatório)
 *   GET  /metrics   - Lista todas as métricas recebidas
 *   GET  /health    - Health check
 */

const express = require('express');
const app = express();

const PORT = process.env.PORT || 3000;
const BEARER_TOKEN = process.env.BEARER_TOKEN || 'meu-token-secreto';

app.use(express.json());

// Armazenamento em memória (substitua por banco de dados em produção)
const metrics = [];

// Middleware de autenticação por Bearer token
function requireAuth(req, res, next) {
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token || token !== BEARER_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// Health check (sem autenticação)
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', metrics_count: metrics.length });
});

// POST /metrics - recebe payload enviado pelo IntegrationService
app.post('/metrics', requireAuth, (req, res) => {
  const body = req.body;

  // Validação mínima dos campos esperados
  const required = ['timestamp', 'voltage', 'current', 'power'];
  const missing = required.filter((k) => body[k] === undefined);
  if (missing.length > 0) {
    return res.status(400).json({ error: 'Missing fields', missing });
  }

  const entry = {
    id: metrics.length + 1,
    received_at: new Date().toISOString(),
    timestamp: body.timestamp,
    voltage: Number(body.voltage),
    current: Number(body.current),
    power: Number(body.power),
    power_factor: body.pf !== undefined ? Number(body.pf) : null,
    frequency: body.frequency !== undefined ? Number(body.frequency) : null,
    energy: body.energy !== undefined ? Number(body.energy) : null,
  };

  metrics.push(entry);
  console.log(`[${entry.received_at}] Métrica recebida #${entry.id}:`, entry);

  res.status(201).json({ ok: true, id: entry.id });
});

// GET /metrics - lista todas as métricas
app.get('/metrics', requireAuth, (req, res) => {
  const limit = Math.min(parseInt(req.query.limit || '100', 10), 1000);
  const page = Math.max(parseInt(req.query.page || '1', 10), 1);
  const start = (page - 1) * limit;

  res.json({
    total: metrics.length,
    page,
    limit,
    data: metrics.slice(start, start + limit),
  });
});

app.listen(PORT, () => {
  console.log(`EMetrics backend de exemplo rodando em http://localhost:${PORT}`);
  console.log(`Bearer token configurado: ${BEARER_TOKEN}`);
  console.log('Configure no app: Base URL = http://<IP>:' + PORT);
});
