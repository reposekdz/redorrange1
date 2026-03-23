'use strict';
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');

r.get('/', authenticate, async (req, res) => {
  try {
    const { page = 1, limit = 50, type } = req.query;
    const offset = (page - 1) * parseInt(limit);
    let sql = `
      SELECT n.*, u.username AS actor_username, u.display_name AS actor_name,
        u.avatar_url AS actor_avatar, u.is_verified AS actor_verified
      FROM notifications n LEFT JOIN users u ON n.actor_id=u.id
      WHERE n.user_id=?
    `;
    const params = [req.userId];
    if (type && type !== 'all') { sql += ' AND n.type=?'; params.push(type); }
    sql += ' ORDER BY n.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    const [notifications, unread, total] = await Promise.all([
      db.query(sql, params),
      db.queryOne('SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND is_read=FALSE', [req.userId]),
      db.queryOne('SELECT COUNT(*) AS c FROM notifications WHERE user_id=?', [req.userId]),
    ]);
    notifications.forEach(n => { n.actor_verified = !!n.actor_verified; });
    res.json({ success: true, notifications, unread_count: unread?.c || 0, total: total?.c || 0, has_more: offset + notifications.length < (total?.c || 0) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/count', authenticate, async (req, res) => {
  const row = await db.queryOne('SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND is_read=FALSE', [req.userId]);
  res.json({ success: true, count: row?.c || 0 });
});

r.get('/unread-count', authenticate, async (req, res) => {
  try {
    const [nc, mc] = await Promise.all([
      db.queryOne('SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND is_read=FALSE', [req.userId]),
      db.queryOne('SELECT COALESCE(SUM(unread_count),0) AS c FROM conversation_members WHERE user_id=? AND left_at IS NULL', [req.userId]),
    ]);
    res.json({ success: true, unread_notifications: nc?.c || 0, unread_messages: mc?.c || 0 });
  } catch (e) { res.status(500).json({ success: false }); }
});

r.put('/:id/read', authenticate, async (req, res) => {
  await db.query('UPDATE notifications SET is_read=TRUE WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

r.post('/read-all', authenticate, async (req, res) => {
  await db.query('UPDATE notifications SET is_read=TRUE WHERE user_id=?', [req.userId]);
  res.json({ success: true });
});

r.post('/push-token', authenticate, async (req, res) => {
  try {
    const { token, platform = 'android' } = req.body;
    if (!token) return res.status(400).json({ success: false });
    await db.query(
      'INSERT INTO push_tokens (user_id, token, platform) VALUES (?,?,?) ON CONFLICT (user_id, token) DO UPDATE SET platform=?, updated_at=NOW()',
      [req.userId, token, platform, platform]
    );
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM notifications WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

r.delete('/', authenticate, async (req, res) => {
  await db.query('DELETE FROM notifications WHERE user_id=?', [req.userId]);
  res.json({ success: true });
});

module.exports = r;
