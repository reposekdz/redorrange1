const rec = require('../services/recommendationEngine');
const express = require('express');
const r = express.Router();
const { authenticate, optionalAuth } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// GET /api/reels/feed
r.get('/feed', authenticate, async (req, res) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const reels = await rec.getRankedReels(req.userId, parseInt(page), parseInt(limit));
    res.json({ success: true, reels, has_more: reels.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels (create)
r.post('/', authenticate, upload.fields([{name:'reel',maxCount:1},{name:'thumbnail',maxCount:1}]), async (req, res) => {
  try {
    const { caption, is_public = 1, music_title, music_artist } = req.body;
    const vid = req.files?.reel?.[0]; const thm = req.files?.thumbnail?.[0];
    if (!vid) return res.status(400).json({ success: false, message: 'Video required' });
    const id = uuidv4();
    const videoUrl = getFileUrl(req, vid.path);
    const thumbUrl = thm ? getFileUrl(req, thm.path) : null;
    await db.query('INSERT INTO reels (id, user_id, video_url, thumbnail_url, caption, is_public, music_title, music_artist) VALUES (?,?,?,?,?,?,?,?)',
      [id, req.userId, videoUrl, thumbUrl, caption || null, is_public ? 1 : 0, music_title || null, music_artist || null]);
    // Parse hashtags
    if (caption) {
      const tags = [...new Set((caption.match(/#(\w+)/g) || []).map(t => t.slice(1).toLowerCase()))];
      for (const tag of tags) {
        let h = await db.queryOne('SELECT id FROM hashtags WHERE name=?', [tag]);
        if (!h) { const hid = uuidv4(); await db.query('INSERT INTO hashtags (id, name) VALUES (?,?)', [hid, tag]); h = { id: hid }; }
        await db.query('INSERT INTO reel_hashtags (reel_id, hashtag_id) VALUES (?,?)', [id, h.id]).catch(() => {});
        await db.query('UPDATE hashtags SET posts_count=posts_count+1 WHERE id=?', [h.id]);
      }
    }
    await db.query('UPDATE users SET reels_count=reels_count+1 WHERE id=?', [req.userId]);
    const reel = await db.queryOne('SELECT r.*, u.username, u.display_name, u.avatar_url FROM reels r JOIN users u ON r.user_id=u.id WHERE r.id=?', [id]);
    if (req.io) req.io.emit('new_reel', { reel });
    res.status(201).json({ success: true, reel });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/reels/:id
r.get('/:id', optionalAuth, async (req, res) => {
  try {
    const uid = req.userId;
    const reel = await db.queryOne(`
      SELECT r.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='reel' AND target_id=r.id AND user_id=?) AS is_liked,
        (SELECT COUNT(*) FROM likes WHERE target_type='reel' AND target_id=r.id) AS likes_count,
        (SELECT COUNT(*) FROM comments WHERE target_type='reel' AND target_id=r.id AND is_deleted=FALSE) AS comments_count
      FROM reels r JOIN users u ON r.user_id=u.id WHERE r.id=? AND r.is_deleted=FALSE
    `, [uid, req.params.id]);
    if (!reel) return res.status(404).json({ success: false, message: 'Not found' });
    reel.is_liked = !!reel.is_liked; reel.is_verified = !!reel.is_verified;
    const comments = await db.query(`
      SELECT c.*, u.username, u.display_name, u.avatar_url FROM comments c
      JOIN users u ON c.user_id=u.id WHERE c.target_type='reel' AND c.target_id=? AND c.is_deleted=FALSE
      ORDER BY c.created_at DESC LIMIT 20
    `, [req.params.id]);
    res.json({ success: true, reel, comments });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels/:id/like
r.post('/:id/like', authenticate, async (req, res) => {
  try {
    const uid = req.userId; const rid = req.params.id;
    const ex = await db.queryOne('SELECT id FROM likes WHERE target_type="reel" AND target_id=? AND user_id=?', [rid, uid]);
    if (ex) {
      await db.query('DELETE FROM likes WHERE id=?', [ex.id]);
      await db.query('UPDATE reels SET likes_count=GREATEST(0,likes_count-1) WHERE id=?', [rid]);
      return res.json({ success: true, liked: false });
    }
    await db.query('INSERT INTO likes (user_id, target_type, target_id) VALUES (?,?,?)', [uid, 'reel', rid]);
    await db.query('UPDATE reels SET likes_count=likes_count+1 WHERE id=?', [rid]);
    const reel = await db.queryOne('SELECT user_id FROM reels WHERE id=?', [rid]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [uid]);
    if (reel && reel.user_id !== uid) await notify(req.io, { userId: reel.user_id, actorId: uid, type: 'reel_like', targetType: 'reel', targetId: rid, message: `${actor?.display_name || actor?.username} liked your reel` });
    const count = await db.queryOne('SELECT likes_count FROM reels WHERE id=?', [rid]);
    res.json({ success: true, liked: true, likes_count: count?.likes_count || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels/:id/view
r.post('/:id/view', authenticate, async (req, res) => {
  try {
    const { watched_pct = 0 } = req.body;
    await db.query('INSERT INTO reel_views (reel_id, viewer_id, watched_pct) VALUES (?,?,?) ON CONFLICT (reel_id, viewer_id) DO UPDATE SET watched_pct=GREATEST(reel_views.watched_pct, ?)', [req.params.id, req.userId, watched_pct, watched_pct]);
    await db.query('UPDATE reels SET views_count=views_count+1 WHERE id=?', [req.params.id]);
    res.json({ success: true });
  } catch (e) { res.json({ success: false }); }
});

// GET /api/reels/:id/comments
r.get('/:id/comments', optionalAuth, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * parseInt(limit);
    const comments = await db.query(`
      SELECT c.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='comment' AND target_id=c.id AND user_id=?) AS is_liked,
        (SELECT COUNT(*) FROM likes WHERE target_type='comment' AND target_id=c.id) AS likes_count
      FROM comments c JOIN users u ON c.user_id=u.id
      WHERE c.target_type='reel' AND c.target_id=? AND c.parent_id IS NULL AND c.is_deleted=FALSE
      ORDER BY c.created_at DESC LIMIT ? OFFSET ?
    `, [req.userId, req.params.id, parseInt(limit), parseInt(offset)]);
    comments.forEach(c => { c.is_liked = !!c.is_liked; c.is_verified = !!c.is_verified; });
    res.json({ success: true, comments, has_more: comments.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels/:id/comments
r.post('/:id/comments', authenticate, async (req, res) => {
  try {
    const { content, parent_id } = req.body;
    if (!content?.trim()) return res.status(400).json({ success: false, message: 'Content required' });
    const id = uuidv4();
    await db.query('INSERT INTO comments (id, user_id, target_type, target_id, content, parent_id) VALUES (?,?,?,?,?,?)',
      [id, req.userId, 'reel', req.params.id, content.trim(), parent_id || null]);
    await db.query('UPDATE reels SET comments_count=comments_count+1 WHERE id=?', [req.params.id]);
    const comment = await db.queryOne('SELECT c.*, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id=u.id WHERE c.id=?', [id]);
    const reel = await db.queryOne('SELECT user_id FROM reels WHERE id=?', [req.params.id]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    if (reel && reel.user_id !== req.userId) await notify(req.io, { userId: reel.user_id, actorId: req.userId, type: 'reel_comment', targetType: 'reel', targetId: req.params.id, message: `${actor?.display_name || actor?.username} commented: ${content.trim().substring(0,50)}` });
    if (req.io) req.io.to(`reel_${req.params.id}`).emit('new_comment', { reel_id: req.params.id, comment });
    res.status(201).json({ success: true, comment });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels/:id/share
r.post('/:id/share', authenticate, async (req, res) => {
  await db.query('UPDATE reels SET shares_count=shares_count+1 WHERE id=?', [req.params.id]).catch(() => {});
  res.json({ success: true });
});

// POST /api/reels/:id/boost
r.post('/:id/boost', authenticate, async (req, res) => {
  try {
    const { budget, currency = 'USD', duration_days = 7 } = req.body;
    const ends = new Date(); ends.setDate(ends.getDate() + parseInt(duration_days));
    const bid = uuidv4();
    await db.query('INSERT INTO post_boosts (id, user_id, reel_id, budget, currency, duration_days, ends_at) VALUES (?,?,?,?,?,?,?)', [bid, req.userId, req.params.id, budget || 0, currency, duration_days, ends]);
    await db.query('UPDATE reels SET is_boosted=1 WHERE id=?', [req.params.id]);
    res.json({ success: true, boost_id: bid, ends_at: ends });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// DELETE /api/reels/:id
r.delete('/:id', authenticate, async (req, res) => {
  const reel = await db.queryOne('SELECT user_id FROM reels WHERE id=?', [req.params.id]);
  if (!reel || reel.user_id !== req.userId) return res.status(403).json({ success: false });
  await db.query('UPDATE reels SET is_deleted=TRUE WHERE id=?', [req.params.id]);
  res.json({ success: true });
});

// GET /api/reels/user/:userId
r.get('/user/:userId', authenticate, async (req, res) => {
  try {
    const reels = await db.query(`
      SELECT r.*, u.username, u.display_name, u.avatar_url FROM reels r
      JOIN users u ON r.user_id=u.id WHERE r.user_id=? AND r.is_deleted=FALSE AND r.is_public=TRUE
      ORDER BY r.created_at DESC LIMIT 30
    `, [req.params.userId]);
    res.json({ success: true, reels });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;

// GET /api/reels/user/:userId
r.get('/user/:userId', authenticate, async (req, res) => {
  try {
    const uid = req.userId; const targetId = req.params.userId;
    const reels = await db.query(`
      SELECT r.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='reel' AND target_id=r.id AND user_id=?) AS is_liked,
        (SELECT COUNT(*) > 0 FROM reel_saves WHERE reel_id=r.id AND user_id=?) AS is_saved
      FROM reels r JOIN users u ON r.user_id=u.id
      WHERE r.user_id=? AND r.is_deleted=FALSE
      ORDER BY r.created_at DESC LIMIT 30
    `, [uid, uid, targetId]);
    reels.forEach(r => { r.is_liked = !!r.is_liked; r.is_saved = !!r.is_saved; r.is_verified = !!r.is_verified; });
    res.json({ success: true, reels });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/reels/:id/save
r.post('/:id/save', authenticate, async (req, res) => {
  try {
    const ex = await db.queryOne('SELECT id FROM reel_saves WHERE reel_id=? AND user_id=?', [req.params.id, req.userId]);
    if (ex) { await db.query('DELETE FROM reel_saves WHERE id=?', [ex.id]); return res.json({ success: true, saved: false }); }
    await db.query('INSERT INTO reel_saves (user_id, reel_id) VALUES (?,?)', [req.userId, req.params.id]);
    res.json({ success: true, saved: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
