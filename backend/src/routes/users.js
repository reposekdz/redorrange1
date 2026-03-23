const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload } = require('../middleware/upload');
const c = require('../controllers/usersController');

r.get('/me', authenticate, async (req, res) => {
  try {
    const db = require('../config/database');
    const user = await db.queryOne(`
      SELECT u.*,
        (SELECT COUNT(*) FROM follows WHERE following_id=u.id AND status='accepted') AS followers_count,
        (SELECT COUNT(*) FROM follows WHERE follower_id=u.id AND status='accepted') AS following_count,
        (SELECT COUNT(*) FROM posts WHERE user_id=u.id AND type NOT IN ('reel','story') AND is_deleted=FALSE) AS posts_count,
        (SELECT COUNT(*) FROM reels WHERE user_id=u.id AND is_deleted=FALSE) AS reels_count,
        (SELECT COUNT(*) FROM notifications WHERE user_id=u.id AND is_read=FALSE) AS unread_notifications
      FROM users u WHERE u.id=?
    `, [req.userId]);
    if (!user) return res.status(404).json({ success: false });
    user.is_verified = !!user.is_verified;
    user.is_private  = !!user.is_private;
    user.is_online   = !!user.is_online;
    user.needs_setup = !!user.needs_setup;
    res.json({ success: true, user });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/blocked',         authenticate, c.getBlocked);
r.get('/activity-log',    authenticate, c.getActivityLog);
r.get('/follow-requests', authenticate, c.getFollowRequests);
r.put('/profile',         authenticate, upload.fields([{name:'avatar',maxCount:1},{name:'cover',maxCount:1}]), c.updateProfile);
r.put('/privacy',         authenticate, c.updatePrivacy);
r.delete('/account',      authenticate, async (req, res) => {
  try {
    const db = require('../config/database');
    await db.query("UPDATE users SET username=NULL, display_name='Deleted User', bio=NULL, avatar_url=NULL, cover_url=NULL WHERE id=?", [req.userId]);
    await db.query('DELETE FROM auth_tokens WHERE user_id=?', [req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:id/posts',          authenticate, c.getUserPosts);
r.get('/:id/followers',      authenticate, c.getFollowers);
r.get('/:id/following',      authenticate, c.getFollowing);
r.get('/:id/mutual',         authenticate, c.getMutual);
r.get('/:id/reels',          authenticate, c.getUserReels);
r.get('/:id/tagged',         authenticate, c.getTaggedPosts);
r.post('/:id/follow',        authenticate, c.followUser || c.toggleFollow);
r.post('/:id/block',         authenticate, c.blockUser || c.toggleBlock);
r.post('/:id/follow-respond',authenticate, c.respondFollowRequest);
r.get('/:id',                authenticate, c.getUser || c.getProfile);

module.exports = r;
