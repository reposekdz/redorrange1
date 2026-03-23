// ================================================================
// storiesController.js
// ================================================================
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');

exports.storiesFeed = async (req, res) => {
  try {
    const uid = req.userId;
    const following = await db.query('SELECT following_id FROM follows WHERE follower_id=? AND status="accepted"', [uid]);
    const ids = [uid, ...following.map(f => f.following_id)];
    const ph  = ids.map(() => '?').join(',');

    const users = await db.query(`
      SELECT DISTINCT u.id, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) FROM stories WHERE user_id=u.id AND is_active=1 AND expires_at>NOW()) AS stories_count,
        (SELECT COUNT(*) FROM story_views sv JOIN stories s ON sv.story_id=s.id
          WHERE s.user_id=u.id AND s.is_active=1 AND sv.viewer_id=?) AS viewed_count
      FROM users u
      WHERE u.id IN (${ph})
        AND EXISTS (SELECT 1 FROM stories WHERE user_id=u.id AND is_active=1 AND expires_at>NOW())
      ORDER BY (u.id=?) DESC, viewed_count < stories_count DESC
    `, [uid, ...ids, uid]);

    res.json({ success: true, story_users: users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.getUserStories = async (req, res) => {
  try {
    const stories = await db.query(`
      SELECT s.*,
        (SELECT COUNT(*) > 0 FROM story_views WHERE story_id=s.id AND viewer_id=?) AS is_viewed
      FROM stories s WHERE s.user_id=? AND s.is_active=1 AND s.expires_at>NOW()
      ORDER BY s.created_at ASC
    `, [req.userId, req.params.userId]);
    stories.forEach(s => s.is_viewed = !!s.is_viewed);
    res.json({ success: true, stories });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.createStory = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, message: 'Media required' });
    const { caption, duration = 5 } = req.body;
    const id         = uuidv4();
    const mediaUrl   = getFileUrl(req, req.file.path);
    const mediaType  = req.file.mimetype.startsWith('video') ? 'video' : 'image';
    const expiresAt  = new Date(Date.now() + 24 * 3600 * 1000);
    await db.query('INSERT INTO stories (id, user_id, media_url, media_type, caption, duration, expires_at) VALUES (?,?,?,?,?,?,?)',
      [id, req.userId, mediaUrl, mediaType, caption || null, parseInt(duration), expiresAt]);
    const story = await db.queryOne('SELECT * FROM stories WHERE id=?', [id]);
    res.status(201).json({ success: true, story });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.deleteStory = async (req, res) => {
  const s = await db.queryOne('SELECT id FROM stories WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  if (!s) return res.status(404).json({ success: false, message: 'Not found' });
  await db.query('UPDATE stories SET is_active=0 WHERE id=?', [req.params.id]);
  res.json({ success: true });
};

exports.viewStory = async (req, res) => {
  try {
    await db.query('INSERT IGNORE INTO story_views (story_id, viewer_id) VALUES (?,?)', [req.params.id, req.userId]);
    await db.query('UPDATE stories SET views_count=views_count+1 WHERE id=?', [req.params.id]);
    const story  = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    const viewer = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    if (story) await notify(req.io, {
      userId: story.user_id, actorId: req.userId,
      type: 'story_view', targetType: 'story', targetId: req.params.id,
      message: `${viewer?.display_name || viewer?.username} viewed your story`,
    });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.getStoryViewers = async (req, res) => {
  const viewers = await db.query(`
    SELECT sv.*, u.username, u.display_name, u.avatar_url FROM story_views sv
    JOIN users u ON sv.viewer_id=u.id
    WHERE sv.story_id=?
    ORDER BY sv.viewed_at DESC
  `, [req.params.id]);
  res.json({ success: true, viewers });
};

exports.replyToStory = async (req, res) => {
  try {
    const { content } = req.body;
    const id = uuidv4();
    await db.query('INSERT INTO story_replies (id, story_id, user_id, content) VALUES (?,?,?,?)', [id, req.params.id, req.userId, content]);
    const story  = await db.queryOne('SELECT user_id FROM stories WHERE id=?', [req.params.id]);
    const actor  = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    if (story) await notify(req.io, {
      userId: story.user_id, actorId: req.userId,
      type: 'story_reply', targetType: 'story', targetId: req.params.id,
      message: `${actor?.display_name || actor?.username} replied: "${content?.substring(0,50)}"`,
    });
    res.status(201).json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.getHighlights = async (req, res) => {
  const highlights = await db.query(`
    SELECT h.*, COUNT(hs.story_id) AS stories_count
    FROM highlights h LEFT JOIN highlight_stories hs ON h.id=hs.highlight_id
    WHERE h.user_id=? GROUP BY h.id ORDER BY h.order_index, h.created_at DESC
  `, [req.params.userId]);
  res.json({ success: true, highlights });
};

exports.createHighlight = async (req, res) => {
  try {
    const { title, story_ids, order_index = 0 } = req.body;
    if (!title) return res.status(400).json({ success: false, message: 'Title required' });
    let coverUrl = null;
    if (req.file) coverUrl = getFileUrl(req, req.file.path);
    const id = uuidv4();
    await db.query('INSERT INTO highlights (id, user_id, title, cover_url, order_index) VALUES (?,?,?,?,?)', [id, req.userId, title, coverUrl, order_index]);
    const ids = Array.isArray(story_ids) ? story_ids : JSON.parse(story_ids || '[]');
    for (let i = 0; i < ids.length; i++) await db.query('INSERT IGNORE INTO highlight_stories (highlight_id, story_id, order_index) VALUES (?,?,?)', [id, ids[i], i]);
    const hl = await db.queryOne('SELECT * FROM highlights WHERE id=?', [id]);
    res.status(201).json({ success: true, highlight: hl });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

exports.deleteHighlight = async (req, res) => {
  await db.query('DELETE FROM highlights WHERE id=? AND user_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
};

module.exports.storiesController = {
  storiesFeed: exports.storiesFeed,
  getUserStories: exports.getUserStories,
  createStory: exports.createStory,
  deleteStory: exports.deleteStory,
  viewStory: exports.viewStory,
  getStoryViewers: exports.getStoryViewers,
  replyToStory: exports.replyToStory,
  getHighlights: exports.getHighlights,
  createHighlight: exports.createHighlight,
  deleteHighlight: exports.deleteHighlight,
};
