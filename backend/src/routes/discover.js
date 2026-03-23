'use strict';
const express = require('express');
const r       = express.Router();
const { authenticate } = require('../middleware/auth');
const db      = require('../config/database');
const rec     = require('../services/recommendationEngine');

// GET /api/discover/explore — full discover page
r.get('/explore', authenticate, async (req, res) => {
  try {
    const uid = req.userId;
    const [posts, reels, hashtags, suggested_users, events, trending] = await Promise.all([
      rec.getTrending(uid, 24),
      db.query(`
        SELECT r.*, u.username, u.display_name, u.avatar_url, u.is_verified,
          (SELECT COUNT(*) > 0 FROM likes WHERE target_type='reel' AND target_id=r.id AND user_id=?) AS is_liked
        FROM reels r JOIN users u ON r.user_id=u.id
        WHERE r.is_public=1
          AND r.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
        ORDER BY r.views_count DESC, r.created_at DESC LIMIT 12
      `, [uid, uid]),
      rec.getTrendingHashtags(20),
      rec.getSuggestedUsers(uid, 10),
      db.query(`
        SELECT e.*, u.username, u.display_name, u.avatar_url
        FROM events e JOIN users u ON e.creator_id=u.id
        WHERE e.event_type='public' AND e.start_datetime > NOW()
          AND e.creator_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
        ORDER BY e.going_count DESC, e.start_datetime ASC LIMIT 6
      `, [uid]),
      db.query(`
        SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified,
          (SELECT media_url FROM post_media WHERE post_id=p.id LIMIT 1) AS thumbnail
        FROM posts p JOIN users u ON p.user_id=u.id
        WHERE p.is_public=1 AND p.is_deleted=0
          AND p.created_at > DATE_SUB(NOW(), INTERVAL 3 DAY)
          AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
        ORDER BY p.likes_count DESC LIMIT 9
      `, [uid]),
    ]);

    reels.forEach(r => { r.is_liked = !!r.is_liked; r.is_verified = !!r.is_verified; });
    suggested_users.forEach(u => { u.is_verified = !!u.is_verified; });
    res.json({ success: true, posts, reels, trending_hashtags: hashtags, suggested_users, upcoming_events: events, trending_posts: trending });
  } catch (e) { console.error('[explore]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/discover/trending — trending posts only
r.get('/trending', authenticate, async (req, res) => {
  try {
    const { limit = 30 } = req.query;
    const posts = await rec.getTrending(req.userId, parseInt(limit));
    res.json({ success: true, posts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/discover/suggested-users
r.get('/suggested-users', authenticate, async (req, res) => {
  try {
    const users = await rec.getSuggestedUsers(req.userId, 20);
    res.json({ success: true, users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/discover/trending-hashtags
r.get('/trending-hashtags', authenticate, async (req, res) => {
  try {
    const hashtags = await rec.getTrendingHashtags(25);
    res.json({ success: true, hashtags });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/discover/similar/:postId
r.get('/similar/:postId', authenticate, async (req, res) => {
  try {
    const posts = await rec.getSimilarPosts(req.params.postId, req.userId, 8);
    res.json({ success: true, posts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
