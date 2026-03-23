'use strict';
const express = require('express');
const r       = express.Router();
const { authenticate } = require('../middleware/auth');
const db      = require('../config/database');
const rec     = require('../services/recommendationEngine');

// GET /api/search?q=...&type=all|users|posts|hashtags|reels|events&page=1
r.get('/', authenticate, async (req, res) => {
  try {
    const { q, type = 'all', page = 1, limit = 20 } = req.query;
    if (!q?.trim()) {
      // Return recent searches when no query
      const history  = await db.query('SELECT DISTINCT query, MAX(created_at) AS last FROM search_history WHERE user_id=? GROUP BY query ORDER BY last DESC LIMIT 10', [req.userId]);
      const trending = await rec.getTrendingHashtags(8);
      const suggested = await rec.getSuggestedUsers(req.userId, 5);
      return res.json({ success: true, history, trending_hashtags: trending, suggested_users: suggested, users: [], posts: [], hashtags: [], reels: [], events: [] });
    }
    const result = await rec.searchWithRelevance(q, req.userId, { type, page: parseInt(page), limit: parseInt(limit) });
    res.json({ success: true, ...result, has_more: result.posts?.length === parseInt(limit) });
  } catch (e) { console.error('[search]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// DELETE /api/search/history
r.delete('/history', authenticate, async (req, res) => {
  await db.query('DELETE FROM search_history WHERE user_id=?', [req.userId]);
  res.json({ success: true });
});

// DELETE /api/search/history/:query
r.delete('/history/:query', authenticate, async (req, res) => {
  await db.query('DELETE FROM search_history WHERE user_id=? AND query=?', [req.userId, req.params.query]);
  res.json({ success: true });
});

// GET /api/search/hashtag/:tag/posts
r.get('/hashtag/:tag', authenticate, async (req, res) => {
  try {
    const { page = 1, limit = 30 } = req.query;
    const offset = (parseInt(page) - 1) * parseInt(limit);
    const tag = req.params.tag.replace('#', '');
    const hashtag = await db.queryOne('SELECT * FROM hashtags WHERE name=?', [tag]);
    const posts = await db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
        (SELECT media_type FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS media_type,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS is_liked
      FROM posts p
      JOIN users u ON p.user_id=u.id
      JOIN post_hashtags ph ON p.id=ph.post_id
      JOIN hashtags h ON ph.hashtag_id=h.id
      WHERE h.name=? AND p.is_public=TRUE AND p.is_deleted=FALSE
      ORDER BY p.likes_count DESC, p.created_at DESC
      LIMIT ? OFFSET ?
    `, [req.userId, tag, parseInt(limit), offset]);
    posts.forEach(p => { p.is_liked = !!p.is_liked; p.is_verified = !!p.is_verified; });
    res.json({ success: true, hashtag: hashtag || { name: tag, posts_count: posts.length }, posts, total: hashtag?.posts_count || posts.length, has_more: posts.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
