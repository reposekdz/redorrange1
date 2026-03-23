// routes/channels.js
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

r.get('/', authenticate, async (req, res) => {
  const { category, page = 1, limit = 20 } = req.query;
  const offset = (page - 1) * limit;
  let sql = `SELECT ch.*, u.username, u.display_name, u.avatar_url,
    (SELECT COUNT(*) > 0 FROM channel_subscriptions WHERE channel_id=ch.id AND user_id=?) AS is_subscribed
    FROM channels ch JOIN users u ON ch.owner_id=u.id WHERE 1=1`;
  const params = [req.userId];
  if (category) { sql += ' AND ch.category=?'; params.push(category); }
  sql += ' ORDER BY ch.subscribers_count DESC LIMIT ? OFFSET ?';
  params.push(parseInt(limit), parseInt(offset));
  const channels = await db.query(sql, params);
  channels.forEach(c => c.is_subscribed = !!c.is_subscribed);
  res.json({ success: true, channels });
});

r.post('/', authenticate, upload.fields([{name:'avatar',maxCount:1},{name:'cover',maxCount:1}]), async (req, res) => {
  try {
    const { name, description, category } = req.body;
    if (!name) return res.status(400).json({ success: false, message: 'Name required' });
    const id = uuidv4();
    const avatarUrl = req.files?.avatar?.[0] ? getFileUrl(req, req.files.avatar[0].path) : null;
    const coverUrl  = req.files?.cover?.[0]  ? getFileUrl(req, req.files.cover[0].path)  : null;
    await db.query('INSERT INTO channels (id, owner_id, name, description, avatar_url, cover_url, category) VALUES (?,?,?,?,?,?,?)',
      [id, req.userId, name, description || null, avatarUrl, coverUrl, category || null]);
    await db.query('INSERT INTO channel_subscriptions (channel_id, user_id) VALUES (?,?)', [id, req.userId]);
    await db.query('UPDATE channels SET subscribers_count=1 WHERE id=?', [id]);
    const channel = await db.queryOne('SELECT * FROM channels WHERE id=?', [id]);
    res.status(201).json({ success: true, channel });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:id', authenticate, async (req, res) => {
  const ch = await db.queryOne(`SELECT ch.*, u.username, u.display_name, u.avatar_url,
    (SELECT COUNT(*) > 0 FROM channel_subscriptions WHERE channel_id=ch.id AND user_id=?) AS is_subscribed
    FROM channels ch JOIN users u ON ch.owner_id=u.id WHERE ch.id=?`, [req.userId, req.params.id]);
  if (!ch) return res.status(404).json({ success: false, message: 'Not found' });
  ch.is_subscribed = !!ch.is_subscribed;
  const posts = await db.query('SELECT * FROM channel_posts WHERE channel_id=? ORDER BY created_at DESC LIMIT 20', [req.params.id]);
  res.json({ success: true, channel: ch, posts });
});

r.post('/:id/subscribe', authenticate, async (req, res) => {
  try {
    const ex = await db.queryOne('SELECT id FROM channel_subscriptions WHERE channel_id=? AND user_id=?', [req.params.id, req.userId]);
    if (ex) {
      await db.query('DELETE FROM channel_subscriptions WHERE channel_id=? AND user_id=?', [req.params.id, req.userId]);
      await db.query('UPDATE channels SET subscribers_count=GREATEST(0,subscribers_count-1) WHERE id=?', [req.params.id]);
      return res.json({ success: true, subscribed: false });
    }
    await db.query('INSERT INTO channel_subscriptions (channel_id, user_id) VALUES (?,?)', [req.params.id, req.userId]);
    await db.query('UPDATE channels SET subscribers_count=subscribers_count+1 WHERE id=?', [req.params.id]);
    res.json({ success: true, subscribed: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/:id/post', authenticate, upload.single('media'), async (req, res) => {
  try {
    const ch = await db.queryOne('SELECT id, owner_id FROM channels WHERE id=?', [req.params.id]);
    if (!ch || ch.owner_id !== req.userId) return res.status(403).json({ success: false, message: 'Not authorized' });
    const { content, media_type = 'text' } = req.body;
    const id = uuidv4();
    const mediaUrl = req.file ? getFileUrl(req, req.file.path) : null;
    await db.query('INSERT INTO channel_posts (id, channel_id, content, media_url, media_type) VALUES (?,?,?,?,?)',
      [id, req.params.id, content || null, mediaUrl, media_type]);
    await db.query('UPDATE channels SET posts_count=posts_count+1 WHERE id=?', [req.params.id]);
    const post = await db.queryOne('SELECT * FROM channel_posts WHERE id=?', [id]);
    const subs = await db.query('SELECT user_id FROM channel_subscriptions WHERE channel_id=? AND user_id!=?', [req.params.id, req.userId]);
    const chan = await db.queryOne('SELECT name FROM channels WHERE id=?', [req.params.id]);
    for (const s of subs) await notify(req.io, { userId: s.user_id, actorId: req.userId, type: 'message', targetType: 'channel', targetId: req.params.id, message: `New post in ${chan?.name}` });
    res.status(201).json({ success: true, post });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;

// GET subscribed channels
r.get('/subscribed', authenticate, async (req, res) => {
  try {
    const channels = await db.query(`
      SELECT ch.*, u.username AS owner_username, u.display_name AS owner_name,
        1 AS is_subscribed
      FROM channel_subscriptions cs
      JOIN channels ch ON cs.channel_id=ch.id
      JOIN users u ON ch.owner_id=u.id
      WHERE cs.user_id=?
      ORDER BY ch.subscribers_count DESC
    `, [req.userId]);
    res.json({ success: true, channels });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /channels/:id/unsubscribe
r.post('/:id/unsubscribe', authenticate, async (req, res) => {
  try {
    await db.query('DELETE FROM channel_subscriptions WHERE channel_id=? AND user_id=?', [req.params.id, req.userId]);
    await db.query('UPDATE channels SET subscribers_count=GREATEST(0,subscribers_count-1) WHERE id=?', [req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
