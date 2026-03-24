require('dotenv').config();
const express     = require('express');
const http        = require('http');
const socketIO    = require('socket.io');
const cors        = require('cors');
const helmet      = require('helmet');
const compression = require('compression');
const morgan      = require('morgan');
const path        = require('path');
const cron        = require('node-cron');

const db            = require('./src/config/database');
const socketHandler = require('./src/socket/socketHandler');

// ── Routes
const authRoutes         = require('./src/routes/auth');
const userRoutes         = require('./src/routes/users');
const contactRoutes      = require('./src/routes/contacts');
const postRoutes         = require('./src/routes/posts');
const storyRoutes        = require('./src/routes/stories');
const reelRoutes         = require('./src/routes/reels');
const messageRoutes      = require('./src/routes/messages');
const eventRoutes        = require('./src/routes/events');
const callRoutes         = require('./src/routes/calls');
const searchRoutes       = require('./src/routes/search');
const notificationRoutes = require('./src/routes/notifications');
const discoverRoutes     = require('./src/routes/discover');
const uploadRoutes       = require('./src/routes/upload');
const groupRoutes        = require('./src/routes/groups');
const interactionRoutes  = require('./src/routes/interactions');
const pollRoutes         = require('./src/routes/polls');
const channelRoutes      = require('./src/routes/channels');
const marketplaceRoutes  = require('./src/routes/marketplace');
const monetizationRoutes = require('./src/routes/monetization');
const adsRoutes = require('./src/routes/ads');
const paymentsRoutes = require('./src/routes/payments');
const advancedRoutes  = require('./src/routes/advanced');
const settingsRoutes     = require('./src/routes/settings');
const adminRoutes = require('./src/routes/admin');

const app    = express();
const server = http.createServer(app);
const io     = socketIO(server, {
  cors: { origin: '*', methods: ['GET','POST','PUT','DELETE'], credentials: true },
  maxHttpBufferSize: 50e6,
  pingTimeout: 60000,
  pingInterval: 25000,
});

// ── Middleware
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(compression());
app.use(cors({ origin: '*', credentials: true, methods: ['GET','POST','PUT','DELETE','PATCH','OPTIONS'] }));
app.use(process.env.NODE_ENV === 'production' ? morgan('combined') : morgan('dev'));
// Stripe webhook needs raw body — must be BEFORE express.json
app.post('/api/payments/stripe/webhook',
  express.raw({ type: 'application/json' }),
  (req, res) => {
    req.io = io;
    require('./src/routes/payments').handle?.(req, res) || paymentsRoutes(req, res);
  }
);

// Stripe webhook needs raw body
app.use('/api/webhooks/stripe', express.raw({type: 'application/json'}));

// Stripe needs raw body for webhook verification
app.use('/api/webhooks/stripe', express.raw({ type: 'application/json' }));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/app', express.static(path.join(__dirname, '..', 'frontend', 'web')));
app.use(express.static(path.join(__dirname, 'public')));

// ── Inject io into every request
app.use((req, _, next) => { req.io = io; next(); });

// ── Health
app.get('/health', async (_, res) => {
  const dbOk = await db.test().catch(() => false);
  res.json({ status: 'ok', version: '2.0.0', app: 'RedOrrange', db: dbOk ? 'ok' : 'error', uptime: Math.round(process.uptime()), ts: new Date().toISOString() });
});

// ── API routes
app.use('/api/auth',          authRoutes);
app.use('/api/users',         userRoutes);
app.use('/api/contacts',      contactRoutes);
app.use('/api/posts',         postRoutes);
app.use('/api/stories',       storyRoutes);
app.use('/api/reels',         reelRoutes);
app.use('/api/messages',      messageRoutes);
app.use('/api/events',        eventRoutes);
app.use('/api/calls',         callRoutes);
app.use('/api/search',        searchRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/discover',      discoverRoutes);
app.use('/api/upload',        uploadRoutes);
app.use('/api/groups',        groupRoutes);
app.use('/api/interactions',  interactionRoutes);
app.use('/api/polls',         pollRoutes);
app.use('/api/channels',      channelRoutes);
app.use('/api/marketplace',   marketplaceRoutes);
app.use('/api/settings',      settingsRoutes);
app.use('/api/admin',         adminRoutes);
// Advanced unified router (analytics, live, starred, close-friends, ai)
app.use('/api',               advancedRoutes);

// ── Socket
socketHandler(io);

// ── Cron jobs
cron.schedule('0 * * * *', async () => {
  try {
    // Expire stories
    await db.query('UPDATE stories SET expires_at=expires_at WHERE expires_at < NOW()').catch(() => {});
    // Expire OTPs
    await db.query('DELETE FROM otp_codes WHERE expires_at < NOW() AND is_used=1').catch(() => {});
    // Expire disappearing messages
    await db.query('DELETE FROM messages WHERE expires_at IS NOT NULL AND expires_at < NOW() AND is_deleted=0').catch(() => {});
    console.log('[Cron] Cleanup done');
  } catch (e) { console.error('[Cron] Error:', e.message); }
});

// Every 5 mins: process scheduled messages
cron.schedule('*/5 * * * *', async () => {
  try {
    const { v4: uuidv4 } = require('uuid');
    const pending = await db.query("SELECT * FROM scheduled_messages WHERE status='pending' AND scheduled_at <= NOW() LIMIT 50");
    for (const sm of pending) {
      const msgId = uuidv4();
      await db.query('INSERT INTO messages (id, conversation_id, sender_id, type, content) VALUES (?,?,?,?,?)',
        [msgId, sm.conversation_id, sm.sender_id, sm.type, sm.content]);
      await db.query("UPDATE scheduled_messages SET status='sent' WHERE id=?", [sm.id]);
      io.to(`conv_${sm.conversation_id}`).emit('new_message', {
        message: { id: msgId, conversation_id: sm.conversation_id, sender_id: sm.sender_id, type: sm.type, content: sm.content, created_at: new Date().toISOString() }
      });
    }
  } catch (e) { console.error('[Cron] Scheduled msgs error:', e.message); }
});

// ── 404
app.use('*', (_, res) => res.status(404).json({ success: false, message: 'Route not found' }));

// ── Error handler
app.use((err, req, res, _) => {
  console.error('[Error]', err.stack);
  res.status(err.status || 500).json({
    success: false,
    message: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
});

const PORT = parseInt(process.env.PORT) || 3000;
server.listen(PORT, async () => {
  console.log(`
╔══════════════════════════════════════╗
║  🔴 RedOrrange API v2.0  :${PORT}    ║
║  ${process.env.NODE_ENV === 'production' ? '🚀 Production' : '🛠️  Development'} Mode              ║
╚══════════════════════════════════════╝`);
  const ok = await db.test().catch(() => false);
  console.log(`[DB] ${ok ? '✅ Connected' : '❌ Failed'}`);
});

module.exports = { app, server, io };
