const express = require('express');
const r = express.Router();
const { authenticate, optionalAuth } = require('../middleware/auth');
const { upload } = require('../middleware/upload');
const c = require('../controllers/postsController');
const db = require('../config/database');

r.get('/feed',                         authenticate, c.getFeed);
r.post('/',                            authenticate, upload.array('post_media', 10), c.createPost);
r.get('/saved',                        authenticate, c.getSaved);
r.get('/:id',                          optionalAuth, c.getPost);
r.delete('/:id',                       authenticate, c.deletePost);
r.post('/:id/like',                    authenticate, c.likePost);
r.post('/:id/save',                    authenticate, c.savePost);
r.post('/:id/share',                   authenticate, c.sharePost);
r.post('/:id/boost',                   authenticate, c.boostPost);
r.get('/:id/comments',                 optionalAuth, c.getComments);
r.post('/:id/comments',                authenticate, c.addComment);


// Comment operations
r.delete('/:id/comments/:commentId', authenticate, async (req, res) => {
  try {
    const comment = await db.queryOne('SELECT id FROM comments WHERE id=? AND (user_id=? OR (SELECT user_id FROM posts WHERE id=?)=?)', [req.params.commentId, req.userId, req.params.id, req.userId]);
    if (!comment) return res.status(403).json({ success: false, message: 'Not authorized' });
    await db.query('UPDATE comments SET is_deleted=TRUE WHERE id=?', [req.params.commentId]);
    await db.query('UPDATE posts SET comments_count=GREATEST(0,comments_count-1) WHERE id=?', [req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/:id/comments/:commentId/like', authenticate, async (req, res) => {
  try {
    const ex = await db.queryOne("SELECT id FROM likes WHERE target_type='comment' AND target_id=? AND user_id=?", [req.params.commentId, req.userId]);
    if (ex) { await db.query("DELETE FROM likes WHERE id=?", [ex.id]); return res.json({ success: true, liked: false }); }
    await db.query("INSERT INTO likes (target_type, target_id, user_id, reaction_type) VALUES ('comment',?,?,'like')", [req.params.commentId, req.userId]);
    res.json({ success: true, liked: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// Reactions
r.get('/:id/reactions', authenticate, async (req, res) => {
  try {
    const reactions = await db.query(`SELECT r.reaction_type, u.id, u.username, u.display_name, u.avatar_url, u.is_verified FROM likes r JOIN users u ON r.user_id=u.id WHERE r.target_type='post' AND r.target_id=? ORDER BY r.created_at DESC LIMIT 100`, [req.params.id]);
    res.json({ success: true, users: reactions });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// View tracking
r.post('/:id/view', async (req, res) => {
  await db.query('UPDATE posts SET views_count=views_count+1 WHERE id=?', [req.params.id]).catch(()=>{});
  res.json({ success: true });
});

module.exports = r;

// GET /api/posts/:id/insights
r.get('/:id/insights', authenticate, async (req, res) => {
  try {
    const post = await db.queryOne('SELECT * FROM posts WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    if (!post) return res.status(404).json({ success: false, message: 'Not found or not your post' });
    const [likes, comments, shares, saves, followers] = await Promise.all([
      db.queryOne('SELECT COUNT(*) AS c FROM likes WHERE target_type="post" AND target_id=?', [req.params.id]),
      db.queryOne('SELECT COUNT(*) AS c FROM comments WHERE target_type="post" AND target_id=? AND is_deleted=FALSE', [req.params.id]),
      db.queryOne('SELECT COUNT(*) AS c FROM shares WHERE post_id=?', [req.params.id]),
      db.queryOne('SELECT COUNT(*) AS c FROM saved_posts WHERE post_id=?', [req.params.id]),
      db.queryOne('SELECT followers_count FROM users WHERE id=?', [req.userId]),
    ]);
    const likeCount = likes?.c || 0; const viewCount = post.views_count || 0;
    const engagement = viewCount > 0 ? ((likeCount + (comments?.c || 0)) / viewCount * 100).toFixed(1) : '0.0';
    const followersCount = followers?.followers_count || 1;
    const followersPct = Math.min(100, Math.round((likeCount / (followersCount || 1)) * 100));
    res.json({ success: true, views_count: viewCount, reach: Math.round(viewCount * 1.2), likes_count: likeCount, comments_count: comments?.c || 0, shares_count: shares?.c || 0, saves_count: saves?.c || 0, engagement_rate: engagement, followers_pct: followersPct });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
