const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');

// GET /api/settings
r.get('/', authenticate, async (req, res) => {
  try {
    let settings = await db.queryOne('SELECT * FROM user_settings WHERE user_id=?', [req.userId]);
    if (!settings) {
      await db.query('INSERT INTO user_settings (user_id) VALUES (?)', [req.userId]);
      settings = await db.queryOne('SELECT * FROM user_settings WHERE user_id=?', [req.userId]);
    }
    let prefs = await db.queryOne('SELECT * FROM notification_preferences WHERE user_id=?', [req.userId]);
    if (!prefs) {
      await db.query('INSERT INTO notification_preferences (user_id) VALUES (?)', [req.userId]);
      prefs = await db.queryOne('SELECT * FROM notification_preferences WHERE user_id=?', [req.userId]);
    }
    res.json({ success: true, settings, notification_preferences: prefs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// PUT /api/settings
r.put('/', authenticate, async (req, res) => {
  try {
    const allowed = ['two_factor_enabled','biometric_enabled','login_alerts','read_receipts','show_online_status','show_last_seen','who_can_message','who_can_call','who_can_see_stories','app_language','theme_mode','auto_download_wifi','auto_download_mobile','font_size'];
    const fields = {};
    for (const k of allowed) { if (req.body[k] !== undefined) fields[k] = req.body[k]; }
    if (Object.keys(fields).length) {
      const sets = Object.keys(fields).map(k => `${k}=?`).join(', ');
      await db.query(`INSERT INTO user_settings (user_id, ${Object.keys(fields).join(',')}) VALUES (?, ${Object.keys(fields).map(() => '?').join(',')}) ON DUPLICATE KEY UPDATE ${sets}`, [req.userId, ...Object.values(fields), ...Object.values(fields)]);
    }
    // Sync some settings to users table
    if ('show_online_status' in fields) await db.query('UPDATE users SET show_online_status=? WHERE id=?', [fields.show_online_status ? 1 : 0, req.userId]);
    if ('show_last_seen' in fields) await db.query('UPDATE users SET show_last_seen=? WHERE id=?', [fields.show_last_seen ? 1 : 0, req.userId]);
    if ('read_receipts' in fields) await db.query('UPDATE users SET read_receipts=? WHERE id=?', [fields.read_receipts ? 1 : 0, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// PUT /api/settings/notifications
r.put('/notifications', authenticate, async (req, res) => {
  try {
    const allowed = ['messages','likes','comments','follows','story_views','mentions','calls','events','live','marketplace','channel_posts','email_digest','push_enabled'];
    const fields = {};
    for (const k of allowed) { if (req.body[k] !== undefined) fields[k] = req.body[k] ? 1 : 0; }
    if (Object.keys(fields).length) {
      const sets = Object.keys(fields).map(k => `${k}=?`).join(', ');
      await db.query(`INSERT INTO notification_preferences (user_id, ${Object.keys(fields).join(',')}) VALUES (?, ${Object.keys(fields).map(() => '?').join(',')}) ON DUPLICATE KEY UPDATE ${sets}`, [req.userId, ...Object.values(fields), ...Object.values(fields)]);
    }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/settings/devices
r.get('/devices', authenticate, async (req, res) => {
  try {
    const devices = await db.query('SELECT id, device_name, platform, ip_address, last_active FROM linked_devices WHERE user_id=? ORDER BY last_active DESC', [req.userId]);
    res.json({ success: true, devices });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// DELETE /api/settings/devices/:id
r.delete('/devices/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM linked_devices WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

// DELETE /api/settings/devices (all except current)
r.delete('/devices', authenticate, async (req, res) => {
  await db.query('DELETE FROM linked_devices WHERE user_id=?', [req.userId]);
  res.json({ success: true });
});

// POST /api/settings/boost/post
r.post('/boost/post', authenticate, async (req, res) => {
  try {
    const { post_id, reel_id, budget, currency = 'USD', duration_days = 7 } = req.body;
    if (!post_id && !reel_id) return res.status(400).json({ success: false, message: 'post_id or reel_id required' });
    const { v4: uuidv4 } = require('uuid');
    const ends = new Date(); ends.setDate(ends.getDate() + parseInt(duration_days));
    const bid = uuidv4();
    await db.query('INSERT INTO post_boosts (id, user_id, post_id, reel_id, budget, currency, duration_days, ends_at) VALUES (?,?,?,?,?,?,?,?)',
      [bid, req.userId, post_id || null, reel_id || null, budget || 0, currency, duration_days, ends]);
    if (post_id) await db.query('UPDATE posts SET is_boosted=1, boost_budget=?, boost_ends_at=? WHERE id=? AND user_id=?', [budget || 0, ends, post_id, req.userId]);
    if (reel_id) await db.query('UPDATE reels SET is_boosted=1 WHERE id=? AND user_id=?', [reel_id, req.userId]);
    res.json({ success: true, boost_id: bid, ends_at: ends });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/settings/boosts
r.get('/boosts', authenticate, async (req, res) => {
  const boosts = await db.query('SELECT * FROM post_boosts WHERE user_id=? ORDER BY created_at DESC', [req.userId]);
  res.json({ success: true, boosts });
});

module.exports = r;
