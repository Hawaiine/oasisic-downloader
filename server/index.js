/**
 * server/index.js — Main Express + Socket.IO server
 *
 * Config is loaded by config.js (which calls dotenv first).
 * So process.env.PORT is correctly set from server/.env before this file runs.
 */
'use strict';

const express      = require('express');
const http         = require('http');
const { Server }   = require('socket.io');
const cors         = require('cors');
const path         = require('path');
const fs           = require('fs');

const CONFIG       = require('./config');
const { initQueue } = require('./services/queue');

const app    = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin:'*', methods:['GET','POST'] },
  transports: ['websocket','polling'],
});

app.set('io', io);
initQueue(io);

// ── Optional Bearer token auth ───────────────────────────────────────────────
// Set AUTH_TOKEN in .env to enable. Without it, all requests pass through.
const AUTH_TOKEN = process.env.AUTH_TOKEN || null;
if (AUTH_TOKEN) {
  app.use('/api/', (req, res, next) => {
    // Skip health check (used by Docker healthcheck and monitoring)
    if (req.path === '/health') return next();
    const header = req.headers.authorization || '';
    if (header === `Bearer ${AUTH_TOKEN}`) return next();
    return res.status(401).json({ error: '未授权，需要有效的 AUTH_TOKEN' });
  });
  console.log('[auth] Bearer token auth enabled');
}

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json({ limit:'10mb' }));
app.use(express.urlencoded({ extended:true }));

// ── API routes ────────────────────────────────────────────────────────────────
app.use('/api/info',     require('./routes/info'));
app.use('/api/download', require('./routes/download'));
app.use('/api/lyrics',   require('./routes/lyrics'));
app.use('/api/tasks',    require('./routes/download')); // list alias
app.use('/api/batch',    require('./routes/batch'));

app.get('/api/health', (_, res) => res.json({ status:'ok', port:CONFIG.PORT, uptime:process.uptime() }));

// ── Frontend static files ─────────────────────────────────────────────────────
if (fs.existsSync(CONFIG.CLIENT_BUILD)) {
  app.use(express.static(CONFIG.CLIENT_BUILD));
  app.get('*', (req, res) => {
    if (req.path.startsWith('/api/') || req.path.startsWith('/downloads/')) return res.status(404).end();
    res.sendFile(path.join(CONFIG.CLIENT_BUILD, 'index.html'));
  });
} else {
  console.warn('[server] client/dist not found — run npm run build inside client/');
}

// ── Socket.IO ─────────────────────────────────────────────────────────────────
io.on('connection', socket => {
  console.log(`[WS] Connected: ${socket.id}`);

  socket.on('subscribe', taskId => {
    if (!taskId || typeof taskId !== 'string') return;
    socket.join(`task:${taskId}`);
  });

  socket.on('disconnect', () => {
    console.log(`[WS] Disconnected: ${socket.id}`);
  });
});

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(CONFIG.PORT, '0.0.0.0', () => {
  console.log(`[server] Listening on http://0.0.0.0:${CONFIG.PORT}`);
  if (process.send) process.send('ready');
});

process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 9000);
});

module.exports = { app, io };
