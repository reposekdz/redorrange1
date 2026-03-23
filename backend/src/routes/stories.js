const express = require('express');
const r = express.Router();
const { authenticate, optionalAuth } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');
const c = require('../controllers/storiesController');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

r.get('/feed',             authenticate,              c.storiesFeed);
r.get('/user/:userId',     optionalAuth,              c.getUserStories);
r.post('/',                authenticate, upload.single('story'), async (req, res) => {
  try {
    const uid = req.userId;
    const { caption, duration = 5, text_overlay, bg_color, music_title, music_artist, type = 'image', is_close_friends = 0 } = req.body;
    const id = uuidv4();
    let mediaUrl = null, mediaType = type;
    if (req.file) {
      mediaUrl = getFileUrl(req, req.file.path);
      mediaType = req.file.mimetype.startsWith('video') ? 'video' : 'image';
    } else if (type === 'text') {
      mediaType = 'text';
    }
    const expiresAt = new Date(Date.now() + 24 * 3600000);
    await db.query(
      'INSERT INTO stories (id, user_id, media_url, media_type, caption, duration, expires_at, text_overlay, bg_color, music_title, music_artist, is_close_friends) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [id, uid, mediaUrl, mediaType, caption || null, parseInt(duration), expiresAt, text_overlay || null, bg_color || '#FF6B35', music_title || null, music_artist || null, is_close_friends ? 1 : 0]
    );
    const story = await db.queryOne('SELECT s.*, u.username, u.display_name, u.avatar_url FROM stories s JOIN users u ON s.user_id=u.id WHERE s.id=?', [id]);
    // Notify followers
    const followers = await db.query('SELECT follower_id FROM follows WHERE following_id=? AND status="accepted" LIMIT 200', [uid]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [uid]);
    for (const f of followers.slice(0, 50)) {
      await notify(req.io, { userId: f.follower_id, actorId: uid, type: 'story_view', targetType: 'story', targetId: id, message: `${actor?.display_name || actor?.username} added to their story` });
    }
    res.status(201).json({ success: true, story });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
});

r.post('/:id/view', authenticate, async (req, res) => {
  try {
    await db.query('INSERT IGNORE INTO story_views (story_id, viewer_id) VALUES (?,?)', [req.params.id, req.userId]);
    await db.query('UPDATE stories SET views_count=views_count+1 WHERE id=?', [req.params.id]);
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    if (story) io.to(`user_${story.user_id}`).emit('story_view', { story_id: req.params.id, viewer_id: req.userId });
    res.json({ success: true });
  } catch (e) { res.json({ success: false }); }
});

r.get('/:id/viewers', authenticate, async (req, res) => {
  try {
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    if (!story || story.user_id !== req.userId) return res.status(403).json({ success: false });
    const viewers = await db.query(`SELECT u.id, u.username, u.display_name, u.avatar_url, sv.created_at AS viewed_at FROM story_views sv JOIN users u ON sv.viewer_id=u.id WHERE sv.story_id=? ORDER BY sv.created_at DESC`, [req.params.id]);
    res.json({ success: true, viewers });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/:id/react', authenticate, async (req, res) => {
  try {
    const { emoji } = req.body;
    if (!emoji) return res.status(400).json({ success: false });
    await db.query('INSERT INTO story_reactions (story_id, user_id, emoji) VALUES (?,?,?) ON DUPLICATE KEY UPDATE emoji=?', [req.params.id, req.userId, emoji, emoji]);
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    if (story && story.user_id !== req.userId) await notify(req.io, { userId: story.user_id, actorId: req.userId, type: 'story_react', targetType: 'story', targetId: req.params.id, message: `${actor?.display_name || actor?.username} reacted ${emoji} to your story` });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/:id', authenticate, c.deleteStory);

// Highlights
r.get('/highlights/:userId', authenticate, async (req, res) => {
  try {
    const hs = await db.query('SELECT h.*, (SELECT COUNT(*) FROM highlight_stories WHERE highlight_id=h.id) AS stories_count, (SELECT s.media_url FROM highlight_stories hs2 JOIN stories s ON hs2.story_id=s.id WHERE hs2.highlight_id=h.id ORDER BY hs2.order_index LIMIT 1) AS cover_url FROM highlights h WHERE h.user_id=? ORDER BY h.created_at DESC', [req.params.userId]);
    res.json({ success: true, highlights: hs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/highlights', authenticate, async (req, res) => {
  try {
    const { title, story_ids } = req.body;
    if (!title || !story_ids?.length) return res.status(400).json({ success: false, message: 'title and story_ids required' });
    const id = uuidv4();
    await db.query('INSERT INTO highlights (id, user_id, title) VALUES (?,?,?)', [id, req.userId, title]);
    for (let i = 0; i < story_ids.length; i++) await db.query('INSERT IGNORE INTO highlight_stories (highlight_id, story_id, order_index) VALUES (?,?,?)', [id, story_ids[i], i]);
    res.status(201).json({ success: true, highlight_id: id });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/highlights/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM highlights WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

module.exports = r;

// GET /api/stories/:id/viewers
r.get('/:id/viewers', authenticate, async (req, res) => {
  try {
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    if (!story || story.user_id !== req.userId) return res.status(403).json({ success: false });
    const viewers = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url, sv.viewed_at
      FROM story_views sv JOIN users u ON sv.viewer_id=u.id
      WHERE sv.story_id=? ORDER BY sv.viewed_at DESC
    `, [req.params.id]);
    res.json({ success: true, viewers });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/stories/:id/reply
r.post('/:id/reply', authenticate, async (req, res) => {
  try {
    const { content } = req.body;
    if (!content?.trim()) return res.status(400).json({ success: false });
    const { v4: uuidv4 } = require('uuid');
    const id = uuidv4();
    await db.query('INSERT INTO story_replies (id, story_id, sender_id, content) VALUES (?,?,?,?)', [id, req.params.id, req.userId, content.trim()]);
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    const me = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    if (story && story.user_id !== req.userId) {
      await require('../services/notificationService').notify(req.io, { userId: story.user_id, actorId: req.userId, type: 'story_reply', targetType: 'story', targetId: req.params.id, message: `${me?.display_name || me?.username} replied to your story: ${content.substring(0,50)}` });
    }
    res.json({ success: true, id });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/stories/:id/react
r.post('/:id/react', authenticate, async (req, res) => {
  try {
    const { emoji } = req.body;
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/stories/highlights/:userId
r.get('/highlights/:userId', authenticate, async (req, res) => {
  try {
    const highlights = await db.query(`
      SELECT h.*, (SELECT media_url FROM stories s JOIN highlight_stories hs ON s.id=hs.story_id WHERE hs.highlight_id=h.id ORDER BY hs.order_index LIMIT 1) AS cover_url
      FROM highlights h WHERE h.user_id=? ORDER BY h.created_at DESC
    `, [req.params.userId]);
    res.json({ success: true, highlights });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// DELETE /api/stories/:id
r.delete('/:id', authenticate, async (req, res) => {
  try {
    await db.query('DELETE FROM stories WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
