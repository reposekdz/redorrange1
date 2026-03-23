const rec = require('../services/recommendationEngine');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');

// ── Feed
exports.getFeed = async (req, res) => {
  try {
    const { page = 1, limit = 15 } = req.query;
    const result = await rec.getRankedFeed(req.userId, parseInt(page), parseInt(limit));
    return res.json({ success: true, ...result });
  } catch (e) {
    console.error('[getFeed]', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
};
exports._getFeedOriginal = async (req, res) => {
  try {
    const uid = req.userId;
    const { page = 1, limit = 10 } = req.query;
    const offset = (page - 1) * parseInt(limit);
    const posts = await db.query(`
      SELECT p.*,
        u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?)::boolean AS is_liked,
        (SELECT COUNT(*) > 0 FROM saved_posts WHERE post_id=p.id AND user_id=?)::boolean AS is_saved,
        (SELECT reaction_type FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS my_reaction,
        (SELECT COUNT(*) FROM likes WHERE target_type='post' AND target_id=p.id) AS likes_count,
        (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND is_deleted=0) AS comments_count,
        (SELECT COUNT(*) FROM shares WHERE post_id=p.id) AS shares_count
      FROM posts p
      JOIN users u ON p.user_id=u.id
      WHERE (p.user_id IN (SELECT following_id FROM follows WHERE follower_id=? AND status='accepted') OR p.user_id=?)
        AND p.type NOT IN ('reel','story') AND p.is_deleted=0
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `, [uid, uid, uid, uid, uid, parseInt(limit), parseInt(offset)]);

    for (const p of posts) {
      p.is_liked = !!p.is_liked; p.is_saved = !!p.is_saved; p.is_verified = !!p.is_verified;
      p.media = await db.query('SELECT * FROM post_media WHERE post_id=? ORDER BY order_index', [p.id]);
    }
    res.json({ success: true, posts, has_more: posts.length === parseInt(limit) });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
};

// ── Create post
exports.createPost = async (req, res) => {
  try {
    const uid = req.userId;
    const { caption, location, type = 'image', is_public = 1, allow_comments = 1 } = req.body;
    const id = uuidv4();
    await db.query('INSERT INTO posts (id, user_id, caption, location, type, is_public, allow_comments) VALUES (?,?,?,?,?,?,?)',
      [id, uid, caption || null, location || null, type, is_public ? 1 : 0, allow_comments ? 1 : 0]);

    // Handle media files
    const files = req.files || [];
    for (let i = 0; i < files.length; i++) {
      const f = files[i];
      const mediaId = uuidv4();
      const url = getFileUrl(req, f.path);
      const mtype = f.mimetype.startsWith('video') ? 'video' : 'image';
      await db.query('INSERT INTO post_media (id, post_id, media_url, media_type, order_index) VALUES (?,?,?,?,?)',
        [mediaId, id, url, mtype, i]);
    }

    await db.query('UPDATE users SET posts_count=posts_count+1 WHERE id=?', [uid]);

    // Parse hashtags
    if (caption) {
      const tags = [...new Set(caption.match(/#(\w+)/g) || [])].map(t => t.slice(1).toLowerCase());
      for (const tag of tags) {
        let h = await db.queryOne('SELECT id FROM hashtags WHERE name=?', [tag]);
        if (!h) { const hid = uuidv4(); await db.query('INSERT INTO hashtags (id, name) VALUES (?,?)', [hid, tag]); h = { id: hid }; }
        await db.query('INSERT INTO post_hashtags (post_id, hashtag_id) VALUES (?,?) ON CONFLICT DO NOTHING', [id, h.id]);
        await db.query('UPDATE hashtags SET posts_count=posts_count+1 WHERE id=?', [h.id]);
      }
    }

    const post = await db.queryOne(`
      SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified FROM posts p JOIN users u ON p.user_id=u.id WHERE p.id=?
    `, [id]);
    post.media = await db.query('SELECT * FROM post_media WHERE post_id=? ORDER BY order_index', [id]);
    post.is_liked = false; post.is_saved = false; post.likes_count = 0; post.comments_count = 0;

    // Notify followers
    if (req.io) req.io.emit('new_post', { post });

    res.status(201).json({ success: true, post });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
};

// ── Get single post
exports.getPost = async (req, res) => {
  try {
    const uid = req.userId;
    const post = await db.queryOne(`
      SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?)::boolean AS is_liked,
        (SELECT COUNT(*) > 0 FROM saved_posts WHERE post_id=p.id AND user_id=?)::boolean AS is_saved,
        (SELECT COUNT(*) FROM likes WHERE target_type='post' AND target_id=p.id) AS likes_count,
        (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND is_deleted=FALSE) AS comments_count
      FROM posts p JOIN users u ON p.user_id=u.id WHERE p.id=? AND p.is_deleted=FALSE
    `, [uid, uid, req.params.id]);
    if (!post) return res.status(404).json({ success: false, message: 'Post not found' });
    post.is_liked = !!post.is_liked; post.is_saved = !!post.is_saved; post.is_verified = !!post.is_verified;
    post.media = await db.query('SELECT * FROM post_media WHERE post_id=? ORDER BY order_index', [post.id]);
    await db.query('UPDATE posts SET views_count=views_count+1 WHERE id=?', [post.id]);
    res.json({ success: true, post });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Like / react
exports.likePost = async (req, res) => {
  try {
    const uid = req.userId; const pid = req.params.id;
    const { reaction_type = 'like' } = req.body;
    const ex = await db.queryOne("SELECT id FROM likes WHERE target_type='post' AND target_id=? AND user_id=?", [pid, uid]);
    if (ex) {
      await db.query('DELETE FROM likes WHERE id=?', [ex.id]);
      await db.query('UPDATE posts SET likes_count=GREATEST(0,likes_count-1) WHERE id=?', [pid]);
      return res.json({ success: true, liked: false });
    }
    await db.query('INSERT INTO likes (user_id, target_type, target_id, reaction_type) VALUES (?,?,?,?)', [uid, 'post', pid, reaction_type]);
    await db.query('UPDATE posts SET likes_count=likes_count+1 WHERE id=?', [pid]);
    const post = await db.queryOne('SELECT user_id FROM posts WHERE id=?', [pid]);
    if (post) {
      const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [uid]);
      await notify(req.io, { userId: post.user_id, actorId: uid, type: 'like', targetType: 'post', targetId: pid, message: `${actor?.display_name || actor?.username} liked your post` });
    }
    if (req.io) req.io.to(`post_${pid}`).emit('post_liked', { post_id: pid, user_id: uid, reaction_type });
    const count = await db.queryOne('SELECT likes_count FROM posts WHERE id=?', [pid]);
    res.json({ success: true, liked: true, likes_count: count?.likes_count || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Comments
exports.getComments = async (req, res) => {
  try {
    const uid = req.userId; const { page = 1, limit = 20, parent_id = null } = req.query;
    const offset = (page - 1) * parseInt(limit);
    const comments = await db.query(`
      SELECT c.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='comment' AND target_id=c.id AND user_id=?)::boolean AS is_liked,
        (SELECT COUNT(*) FROM likes WHERE target_type='comment' AND target_id=c.id) AS likes_count
      FROM comments c JOIN users u ON c.user_id=u.id
      WHERE c.target_type='post' AND c.target_id=? AND c.parent_id ${parent_id ? '=?' : 'IS NULL'} AND c.is_deleted=FALSE
      ORDER BY c.created_at DESC LIMIT ? OFFSET ?
    `, parent_id ? [uid, req.params.id, parent_id, parseInt(limit), parseInt(offset)] : [uid, req.params.id, parseInt(limit), parseInt(offset)]);
    comments.forEach(c => { c.is_liked = !!c.is_liked; c.is_verified = !!c.is_verified; });
    res.json({ success: true, comments, has_more: comments.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.addComment = async (req, res) => {
  try {
    const uid = req.userId; const pid = req.params.id;
    const { content, parent_id } = req.body;
    if (!content?.trim()) return res.status(400).json({ success: false, message: 'Content required' });
    const id = uuidv4();
    await db.query('INSERT INTO comments (id, user_id, target_type, target_id, content, parent_id) VALUES (?,?,?,?,?,?)',
      [id, uid, 'post', pid, content.trim(), parent_id || null]);
    await db.query('UPDATE posts SET comments_count=comments_count+1 WHERE id=?', [pid]);
    if (parent_id) await db.query('UPDATE comments SET replies_count=replies_count+1 WHERE id=?', [parent_id]);

    const comment = await db.queryOne('SELECT c.*, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id=u.id WHERE c.id=?', [id]);

    const post = await db.queryOne('SELECT user_id FROM posts WHERE id=?', [pid]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [uid]);
    if (post && post.user_id !== uid) await notify(req.io, { userId: post.user_id, actorId: uid, type: 'comment', targetType: 'post', targetId: pid, message: `${actor?.display_name || actor?.username} commented: ${content.trim().substring(0, 50)}` });

    if (req.io) req.io.to(`post_${pid}`).emit('new_comment', { post_id: pid, comment });
    res.status(201).json({ success: true, comment });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Save / Unsave
exports.savePost = async (req, res) => {
  try {
    const uid = req.userId; const pid = req.params.id;
    const ex = await db.queryOne('SELECT id FROM saved_posts WHERE user_id=? AND post_id=?', [uid, pid]);
    if (ex) { await db.query('DELETE FROM saved_posts WHERE id=?', [ex.id]); return res.json({ success: true, saved: false }); }
    await db.query('INSERT INTO saved_posts (user_id, post_id) VALUES (?,?)', [uid, pid]);
    res.json({ success: true, saved: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Share
exports.sharePost = async (req, res) => {
  try {
    const uid = req.userId; const pid = req.params.id;
    await db.query('INSERT INTO shares (user_id, post_id) VALUES (?,?) ON CONFLICT DO NOTHING', [uid, pid]).catch(() => {});
    await db.query('UPDATE posts SET shares_count=shares_count+1 WHERE id=?', [pid]);
    const post = await db.queryOne('SELECT user_id FROM posts WHERE id=?', [pid]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [uid]);
    if (post && post.user_id !== uid) await notify(req.io, { userId: post.user_id, actorId: uid, type: 'share', targetType: 'post', targetId: pid, message: `${actor?.display_name || actor?.username} shared your post` });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Delete post
exports.deletePost = async (req, res) => {
  try {
    const pid = req.params.id;
    const post = await db.queryOne('SELECT user_id FROM posts WHERE id=?', [pid]);
    if (!post) return res.status(404).json({ success: false, message: 'Post not found' });
    if (post.user_id !== req.userId) return res.status(403).json({ success: false, message: 'Not authorized' });
    await db.query('UPDATE posts SET is_deleted=TRUE WHERE id=?', [pid]);
    await db.query('UPDATE users SET posts_count=GREATEST(0,posts_count-1) WHERE id=?', [req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Saved posts
exports.getSaved = async (req, res) => {
  try {
    const uid = req.userId;
    const posts = await db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
      FROM saved_posts sp JOIN posts p ON sp.post_id=p.id JOIN users u ON p.user_id=u.id
      WHERE sp.user_id=? AND p.is_deleted=0 ORDER BY sp.created_at DESC
    `, [uid]);
    res.json({ success: true, posts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// ── Boost reel / post
exports.boostPost = async (req, res) => {
  try {
    const { budget, duration_days = 7, target_audience } = req.body;
    const pid = req.params.id;
    const endDate = new Date(); endDate.setDate(endDate.getDate() + parseInt(duration_days));
    await db.query('UPDATE posts SET is_boosted=1, boost_budget=?, boost_ends_at=? WHERE id=? AND user_id=?',
      [budget || 0, endDate.toISOString(), pid, req.userId]);
    res.json({ success: true, message: 'Post boosted successfully', ends_at: endDate });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};
