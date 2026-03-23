// routes/interactions.js - All engagement actions
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');
const { notify } = require('../services/notificationService');
const { v4: uuidv4 } = require('uuid');

// ── Like a comment
r.post('/comments/:id/like', authenticate, async (req, res) => {
  try {
    const ex = await db.queryOne('SELECT id FROM likes WHERE user_id=? AND target_type="comment" AND target_id=?', [req.userId, req.params.id]);
    if (ex) {
      await db.query('DELETE FROM likes WHERE user_id=? AND target_type="comment" AND target_id=?', [req.userId, req.params.id]);
      await db.query('UPDATE comments SET likes_count=GREATEST(0,likes_count-1) WHERE id=?', [req.params.id]);
    } else {
      await db.query('INSERT INTO likes (user_id, target_type, target_id) VALUES (?,?,?)', [req.userId, 'comment', req.params.id]);
      await db.query('UPDATE comments SET likes_count=likes_count+1 WHERE id=?', [req.params.id]);
    }
    const c = await db.queryOne('SELECT likes_count FROM comments WHERE id=?', [req.params.id]);
    res.json({ success: true, liked: !ex, likes_count: c?.likes_count ?? 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Delete a comment
r.delete('/comments/:id', authenticate, async (req, res) => {
  try {
    const comment = await db.queryOne('SELECT * FROM comments WHERE id=?', [req.params.id]);
    if (!comment) return res.status(404).json({ success: false, message: 'Comment not found' });
    // Allow comment owner or post/reel owner
    const isOwner = comment.user_id === req.userId;
    if (!isOwner) {
      const targetOwner = await db.queryOne(
        comment.target_type === 'post' ? 'SELECT user_id FROM posts WHERE id=?' : 'SELECT user_id FROM reels WHERE id=?',
        [comment.target_id]
      );
      if (targetOwner?.user_id !== req.userId) return res.status(403).json({ success: false, message: 'Not authorized' });
    }
    await db.query('UPDATE comments SET is_deleted=1 WHERE id=?', [req.params.id]);
    if (comment.parent_id) await db.query('UPDATE comments SET replies_count=GREATEST(0,replies_count-1) WHERE id=?', [comment.parent_id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Get comment replies
r.get('/comments/:id/replies', authenticate, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const replies = await db.query(`
      SELECT c.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='comment' AND target_id=c.id AND user_id=?) AS is_liked,
        (SELECT COUNT(*) FROM likes WHERE target_type='comment' AND target_id=c.id) AS likes_count
      FROM comments c JOIN users u ON c.user_id=u.id
      WHERE c.parent_id=? AND c.is_deleted=0
      ORDER BY c.created_at ASC LIMIT ? OFFSET ?
    `, [req.userId, req.params.id, parseInt(limit), (page-1)*parseInt(limit)]);
    replies.forEach(r => { r.is_liked = !!r.is_liked; r.is_verified = !!r.is_verified; });
    res.json({ success: true, replies });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── React to story (emoji reaction)
r.post('/stories/:id/react', authenticate, async (req, res) => {
  try {
    const { emoji } = req.body;
    const story = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    if (!story) return res.status(404).json({ success: false, message: 'Story not found' });
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    await notify(req.io, {
      userId: story.user_id, actorId: req.userId,
      type: 'story_view', targetType: 'story', targetId: req.params.id,
      message: `${actor?.display_name || actor?.username} reacted ${emoji} to your story`,
    });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Check if username available
r.get('/check-username', async (req, res) => {
  const { username } = req.query;
  if (!username) return res.status(400).json({ success: false });
  const ex = await db.queryOne('SELECT id FROM users WHERE username=?', [username]);
  res.json({ success: true, available: !ex });
});

// ── Follow requests management
r.get('/follow-requests', authenticate, async (req, res) => {
  const requests = await db.query(`
    SELECT f.id, f.created_at, u.id AS user_id, u.username, u.display_name, u.avatar_url, u.is_verified
    FROM follows f JOIN users u ON f.follower_id=u.id
    WHERE f.following_id=? AND f.status='pending'
    ORDER BY f.created_at DESC
  `, [req.userId]);
  requests.forEach(r => r.is_verified = !!r.is_verified);
  res.json({ success: true, requests });
});

r.post('/follow-requests/:followId/accept', authenticate, async (req, res) => {
  try {
    const follow = await db.queryOne('SELECT * FROM follows WHERE id=? AND following_id=?', [req.params.followId, req.userId]);
    if (!follow) return res.status(404).json({ success: false, message: 'Request not found' });
    await db.query('UPDATE follows SET status="accepted" WHERE id=?', [req.params.followId]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    await notify(req.io, { userId: follow.follower_id, actorId: req.userId, type: 'follow', message: `${actor?.display_name || actor?.username} accepted your follow request` });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/follow-requests/:followId', authenticate, async (req, res) => {
  await db.query('DELETE FROM follows WHERE id=? AND following_id=?', [req.params.followId, req.userId]);
  res.json({ success: true });
});

// ── Get post likes with users
r.get('/posts/:id/likes', authenticate, async (req, res) => {
  const users = await db.query(`
    SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified, l.reaction_type,
      (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id) AS is_following
    FROM likes l JOIN users u ON l.user_id=u.id
    WHERE l.target_type='post' AND l.target_id=?
    ORDER BY l.created_at DESC LIMIT 50
  `, [req.userId, req.params.id]);
  users.forEach(u => { u.is_following = !!u.is_following; u.is_verified = !!u.is_verified; });
  res.json({ success: true, users });
});

// ── Saved collections
r.get('/saved-collections', authenticate, async (req, res) => {
  const collections = [
    { id: 'all', name: 'All Posts', count: 0 },
  ];
  const count = await db.queryOne('SELECT COUNT(*) AS c FROM saved_posts WHERE user_id=?', [req.userId]);
  collections[0].count = count?.c ?? 0;
  res.json({ success: true, collections });
});

// ── Search users to tag
r.get('/search-users', authenticate, async (req, res) => {
  const { q } = req.query;
  if (!q || q.length < 2) return res.json({ success: true, users: [] });
  const users = await db.query(`
    SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified
    FROM users u WHERE (u.username LIKE ? OR u.display_name LIKE ?) AND u.username IS NOT NULL LIMIT 10
  `, [`%${q}%`, `%${q}%`]);
  res.json({ success: true, users });
});

module.exports = r;
