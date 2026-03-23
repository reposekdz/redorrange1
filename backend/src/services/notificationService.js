const db    = require('../config/database');
const { v4: uuidv4 } = require('uuid');

async function notify(io, { userId, actorId, type, targetType, targetId, message, extra = {} }) {
  try {
    if (userId === actorId) return null;
    const prefs = await db.queryOne('SELECT * FROM notification_preferences WHERE user_id=?', [userId]).catch(() => null);
    if (prefs) {
      const map = { like:'likes', reaction:'likes', comment:'comments', comment_reply:'comments', follow:'follows', follow_request:'follows', follow_accepted:'follows', message:'messages', call:'calls', story_view:'stories', story_reply:'stories', live:'live' };
      const key = map[type];
      if (key && prefs[key] === false) return null;
    }
    const id = uuidv4();
    await db.query('INSERT INTO notifications (id, user_id, actor_id, type, target_type, target_id, message) VALUES (?,?,?,?,?,?,?)', [id, userId, actorId || null, type, targetType || null, targetId || null, message || null]);
    const actor = actorId ? await db.queryOne('SELECT id, username, display_name, avatar_url FROM users WHERE id=?', [actorId]).catch(() => null) : null;
    const notification = { id, type, target_type: targetType || null, target_id: targetId || null, message: message || null, is_read: false, created_at: new Date().toISOString(), actor_id: actorId || null, actor_username: actor?.username || null, actor_name: actor?.display_name || null, actor_avatar: actor?.avatar_url || null, ...extra };
    if (io) io.to(`user_${userId}`).emit('notification', { notification });
    const unread = await db.queryOne('SELECT COUNT(*) AS c FROM notifications WHERE user_id=? AND is_read=FALSE', [userId]).catch(() => ({ c: 0 }));
    if (io) io.to(`user_${userId}`).emit('unread_count', { notifications: unread?.c || 0 });
    return notification;
  } catch (e) { console.error('[notify]', e.message); return null; }
}

async function notifyFollowers(io, userId, opts, limit = 50) {
  try {
    const followers = await db.query("SELECT follower_id FROM follows WHERE following_id=? AND status='accepted' LIMIT ?", [userId, limit]);
    for (const f of followers) await notify(io, { ...opts, userId: f.follower_id });
  } catch (e) { console.error('[notifyFollowers]', e.message); }
}

module.exports = { notify, notifyFollowers };
