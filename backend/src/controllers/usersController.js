const db = require('../config/database');
const { getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');

// GET /api/users/:id
exports.getProfile = exports.getUser = async (req, res) => {
  try {
    const user = await db.queryOne(`
      SELECT u.id, u.username, u.display_name, u.bio, u.avatar_url, u.cover_url,
        u.website, u.location, u.gender, u.is_verified, u.is_private, u.is_online,
        u.last_seen, u.status_text, u.created_at,
        (SELECT COUNT(*) FROM follows WHERE following_id=u.id AND status='accepted') AS followers_count,
        (SELECT COUNT(*) FROM follows WHERE follower_id=u.id  AND status='accepted') AS following_count,
        (SELECT COUNT(*) FROM posts  WHERE user_id=u.id AND is_public=TRUE) AS posts_count,
        (SELECT COUNT(*) FROM reels  WHERE user_id=u.id AND is_public=TRUE) AS reels_count,
        (SELECT status  FROM follows WHERE follower_id=? AND following_id=u.id) AS follow_status,
        (SELECT COUNT(*) > 0 FROM blocks WHERE blocker_id=? AND blocked_id=u.id) AS is_blocked,
        (SELECT COUNT(*) > 0 FROM blocks WHERE blocker_id=u.id AND blocked_id=?) AS blocked_me
      FROM users u
      WHERE u.id=? OR u.username=?
    `, [req.userId, req.userId, req.userId, req.params.id, req.params.id]);

    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    user.is_blocked  = !!user.is_blocked;
    user.blocked_me  = !!user.blocked_me;
    user.is_online   = !!user.is_online;
    user.is_verified = !!user.is_verified;
    user.is_private  = !!user.is_private;
    res.json({ success: true, user });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// PUT /api/users/profile
exports.updateProfile = async (req, res) => {
  try {
    const { display_name, bio, website, location, gender, status_text, is_private, date_of_birth } = req.body;
    const fields = {};
    if (display_name  !== undefined) fields.display_name  = display_name;
    if (bio           !== undefined) fields.bio           = bio;
    if (website       !== undefined) fields.website       = website;
    if (location      !== undefined) fields.location      = location;
    if (gender        !== undefined) fields.gender        = gender;
    if (status_text   !== undefined) fields.status_text   = status_text;
    if (date_of_birth !== undefined) fields.date_of_birth = date_of_birth;
    if (is_private    !== undefined) fields.is_private    = is_private === 'true' || is_private === true ? 1 : 0;

    if (req.files?.avatar?.[0]) fields.avatar_url = getFileUrl(req, req.files.avatar[0].path);
    if (req.files?.cover?.[0])  fields.cover_url  = getFileUrl(req, req.files.cover[0].path);

    if (!Object.keys(fields).length) return res.status(400).json({ success: false, message: 'Nothing to update' });

    const sets   = Object.keys(fields).map(k => `${k}=?`).join(', ');
    const values = [...Object.values(fields), req.userId];
    await db.query(`UPDATE users SET ${sets}, updated_at=NOW() WHERE id=?`, values);

    const user = await db.queryOne('SELECT * FROM users WHERE id=?', [req.userId]);
    res.json({ success: true, user });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/users/:id/follow
exports.followUser = exports.toggleFollow = async (req, res) => {
  try {
    const targetId = req.params.id;
    if (targetId === req.userId) return res.status(400).json({ success: false, message: 'Cannot follow yourself' });

    const existing = await db.queryOne('SELECT id FROM follows WHERE follower_id=? AND following_id=?', [req.userId, targetId]);
    if (existing) {
      await db.query('DELETE FROM follows WHERE follower_id=? AND following_id=?', [req.userId, targetId]);
      return res.json({ success: true, following: false });
    }

    const target = await db.queryOne('SELECT is_private FROM users WHERE id=?', [targetId]);
    const status = target?.is_private ? 'pending' : 'accepted';
    await db.query('INSERT INTO follows (follower_id, following_id, status) VALUES (?,?,?)', [req.userId, targetId, status]);

    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    await notify(req.io, {
      userId: targetId, actorId: req.userId,
      type: status === 'pending' ? 'follow_request' : 'follow',
      message: `${actor?.display_name || actor?.username} started following you`,
    });

    res.json({ success: true, following: true, status });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/users/:id/followers
exports.getFollowers = async (req, res) => {
  const { page = 1, limit = 30 } = req.query;
  const offset = (page - 1) * limit;
  const followers = await db.query(`
    SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id AND status='accepted') AS is_following
    FROM follows f JOIN users u ON f.follower_id=u.id
    WHERE f.following_id=? AND f.status='accepted'
    ORDER BY f.created_at DESC LIMIT ? OFFSET ?
  `, [req.userId, req.params.id, parseInt(limit), parseInt(offset)]);
  followers.forEach(u => { u.is_following = !!u.is_following; u.is_verified = !!u.is_verified; });
  res.json({ success: true, followers });
};

// GET /api/users/:id/following
exports.getFollowing = async (req, res) => {
  const { page = 1, limit = 30 } = req.query;
  const offset = (page - 1) * limit;
  const following = await db.query(`
    SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id AND status='accepted') AS is_following
    FROM follows f JOIN users u ON f.following_id=u.id
    WHERE f.follower_id=? AND f.status='accepted'
    ORDER BY f.created_at DESC LIMIT ? OFFSET ?
  `, [req.userId, req.params.id, parseInt(limit), parseInt(offset)]);
  following.forEach(u => { u.is_following = !!u.is_following; u.is_verified = !!u.is_verified; });
  res.json({ success: true, following });
};

// GET /api/users/:id/posts
exports.getUserPosts = async (req, res) => {
  const { page = 1, limit = 12 } = req.query;
  const offset = (page - 1) * limit;
  const posts = await db.query(`
    SELECT p.*, u.username, u.display_name, u.avatar_url,
      (SELECT COUNT(*) FROM likes WHERE target_type='post' AND target_id=p.id) AS likes_count,
      (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND is_deleted=FALSE) AS comments_count,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
    FROM posts p JOIN users u ON p.user_id=u.id
    WHERE p.user_id=? AND p.is_public=TRUE
    ORDER BY p.created_at DESC LIMIT ? OFFSET ?
  `, [req.params.id, parseInt(limit), parseInt(offset)]);
  res.json({ success: true, posts });
};

// POST /api/users/:id/block
exports.blockUser = exports.toggleBlock = async (req, res) => {
  try {
    const ex = await db.queryOne('SELECT id FROM blocks WHERE blocker_id=? AND blocked_id=?', [req.userId, req.params.id]);
    if (ex) {
      await db.query('DELETE FROM blocks WHERE blocker_id=? AND blocked_id=?', [req.userId, req.params.id]);
      return res.json({ success: true, blocked: false });
    }
    await db.query('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?,?)', [req.userId, req.params.id]);
    await db.query('DELETE FROM follows WHERE (follower_id=? AND following_id=?) OR (follower_id=? AND following_id=?)',
      [req.userId, req.params.id, req.params.id, req.userId]);
    res.json({ success: true, blocked: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/users/:id/reels
exports.getUserReels = async (req, res) => {
  const { page = 1, limit = 9 } = req.query;
  const offset = (page - 1) * limit;
  const reels = await db.query(
    'SELECT * FROM reels WHERE user_id=? AND is_public=TRUE ORDER BY created_at DESC LIMIT ? OFFSET ?',
    [req.params.id, parseInt(limit), parseInt(offset)]
  );
  res.json({ success: true, reels });
};

// GET /api/users/blocked
exports.getBlocked = async (req, res) => {
  try {
    const users = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url FROM blocks b
      JOIN users u ON b.blocked_id=u.id WHERE b.blocker_id=?
    `, [req.userId]);
    res.json({ success: true, blocked: users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// PUT /api/users/privacy
exports.updatePrivacy = async (req, res) => {
  try {
    const { is_private, read_receipts, online_status, last_seen, who_can_message, who_can_call, who_can_see_stories } = req.body;
    const updates = {};
    if (is_private !== undefined) updates.is_private = is_private ? 1 : 0;
    if (read_receipts !== undefined) updates.read_receipts = read_receipts ? 1 : 0;
    if (online_status !== undefined) updates.show_online_status = online_status ? 1 : 0;
    if (last_seen !== undefined) updates.show_last_seen = last_seen ? 1 : 0;
    const sets = Object.keys(updates).map(k => `${k}=?`).join(', ');
    if (sets) await db.query(`UPDATE users SET ${sets} WHERE id=?`, [...Object.values(updates), req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/users/:id/mutual
exports.getMutual = async (req, res) => {
  try {
    const users = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url FROM follows f1
      JOIN follows f2 ON f1.follower_id=f2.follower_id
      JOIN users u ON f1.follower_id=u.id
      WHERE f1.following_id=? AND f2.following_id=? AND f1.status='accepted' AND f2.status='accepted'
    `, [req.userId, req.params.id]);
    res.json({ success: true, mutual: users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/users/activity-log
exports.getActivityLog = async (req, res) => {
  try {
    // Pull from notifications as activity proxy
    const activities = await db.query(`
      SELECT type, message AS description, created_at FROM notifications
      WHERE actor_id=? ORDER BY created_at DESC LIMIT 50
    `, [req.userId]);
    res.json({ success: true, activities });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.getFollowRequests = async (req, res) => {
  try {
    const requests = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified, f.created_at AS requested_at
      FROM follows f JOIN users u ON f.follower_id=u.id
      WHERE f.following_id=? AND f.status='pending'
      ORDER BY f.created_at DESC
    `, [req.userId]);
    res.json({ success: true, requests });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.respondFollowRequest = async (req, res) => {
  try {
    const { action } = req.body;
    if (action === 'accept') {
      await db.query("UPDATE follows SET status='accepted' WHERE follower_id=? AND following_id=?", [req.params.id, req.userId]);
      await db.query('UPDATE users SET followers_count=followers_count+1 WHERE id=?', [req.userId]);
    } else {
      await db.query("DELETE FROM follows WHERE follower_id=? AND following_id=? AND status='pending'", [req.params.id, req.userId]);
    }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.getTaggedPosts = async (req, res) => {
  try {
    const posts = await db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
      FROM post_tags pt JOIN posts p ON pt.post_id=p.id JOIN users u ON p.user_id=u.id
      WHERE pt.tagged_user_id=? AND p.is_deleted=FALSE
      ORDER BY p.created_at DESC LIMIT 30
    `, [req.params.id]);
    res.json({ success: true, posts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};
