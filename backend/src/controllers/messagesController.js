const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');

// ── helpers
const convQuery = (userId) => `
  SELECT c.id, c.type, c.name, c.avatar_url, c.description, c.last_message_at,
    cm.muted_until, cm.last_read_message_id, cm.role,
    (SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id AND m.is_deleted=FALSE
      AND m.sender_id!=? AND (cm.last_read_message_id IS NULL OR m.id > cm.last_read_message_id)) AS unread_count,
    lm.content AS lm_content, lm.type AS lm_type, lm.sender_id AS lm_sender,
    lm.created_at AS lm_at, lmu.display_name AS lm_sender_name,
    ou.id AS other_id, ou.username AS other_username, ou.display_name AS other_display_name,
    ou.avatar_url AS other_avatar_url, ou.is_online AS other_is_online,
    ou.last_seen AS other_last_seen, ou.is_verified AS other_is_verified,
    ou.status_text AS other_status_text
  FROM conversations c
  JOIN conversation_members cm ON c.id=cm.conversation_id AND cm.user_id=? AND cm.left_at IS NULL
  LEFT JOIN messages lm ON c.last_message_id=lm.id AND lm.is_deleted=FALSE
  LEFT JOIN users lmu ON lm.sender_id=lmu.id
  LEFT JOIN conversation_members cm2 ON c.id=cm2.conversation_id AND cm2.user_id!=? AND c.type='direct' AND cm2.left_at IS NULL
  LEFT JOIN users ou ON cm2.user_id=ou.id AND c.type='direct'
`;

// GET /api/messages/conversations
exports.getConversations = async (req, res) => {
  try {
    const uid = req.userId;
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;
    const conversations = await db.query(
      `${convQuery(uid)} ORDER BY c.last_message_at DESC, c.created_at DESC LIMIT ? OFFSET ?`,
      [uid, uid, uid, parseInt(limit), parseInt(offset)]
    );
    for (const c of conversations) {
      c.other_is_online  = !!c.other_is_online;
      c.other_is_verified = !!c.other_is_verified;
      if (c.type === 'group') {
        c.members = await db.query(`
          SELECT u.id, u.username, u.display_name, u.avatar_url FROM conversation_members cm
          JOIN users u ON cm.user_id=u.id WHERE cm.conversation_id=? AND cm.left_at IS NULL LIMIT 4
        `, [c.id]);
        const r = await db.queryOne('SELECT COUNT(*) AS cnt FROM conversation_members WHERE conversation_id=? AND left_at IS NULL', [c.id]);
        c.members_count = r.cnt;
      }
    }
    res.json({ success: true, conversations });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations
exports.createConversation = async (req, res) => {
  try {
    const uid = req.userId;
    const { type = 'direct', user_id, user_ids, name, description } = req.body;

    if (type === 'direct') {
      if (!user_id) return res.status(400).json({ success: false, message: 'user_id required' });
      const existing = await db.queryOne(`
        SELECT c.id FROM conversations c
        JOIN conversation_members cm1 ON c.id=cm1.conversation_id AND cm1.user_id=?
        JOIN conversation_members cm2 ON c.id=cm2.conversation_id AND cm2.user_id=?
        WHERE c.type='direct' LIMIT 1
      `, [uid, user_id]);
      if (existing) {
        const conv = await db.queryOne(`${convQuery(uid)} WHERE c.id=?`, [uid, uid, uid, existing.id]);
        return res.json({ success: true, conversation: conv, existing: true });
      }
      const id = uuidv4();
      await db.query('INSERT INTO conversations (id, type, created_by) VALUES (?,?,?)', [id, 'direct', uid]);
      await db.query('INSERT INTO conversation_members (conversation_id, user_id) VALUES (?,?),(?,?)', [id, uid, id, user_id]);
      const conv = await db.queryOne(`${convQuery(uid)} WHERE c.id=?`, [uid, uid, uid, id]);
      if (req.io) req.io.to(`user_${user_id}`).emit('new_conversation', { conversation: conv });
      return res.status(201).json({ success: true, conversation: conv });
    }

    // Group
    if (!name) return res.status(400).json({ success: false, message: 'name required' });
    const members = Array.isArray(user_ids) ? user_ids : JSON.parse(user_ids || '[]');
    let avatarUrl = null;
    if (req.file) avatarUrl = getFileUrl(req, req.file.path);
    const id = uuidv4();
    await db.query('INSERT INTO conversations (id, type, name, description, avatar_url, created_by) VALUES (?,?,?,?,?,?)',
      [id, 'group', name, description || null, avatarUrl, uid]);
    const allMembers = [...new Set([uid, ...members])];
    for (const m of allMembers) {
      await db.query('INSERT INTO conversation_members (conversation_id, user_id, role) VALUES (?,?,?)', [id, m, m === uid ? 'owner' : 'member']);
    }
    const conv = await db.queryOne(`${convQuery(uid)} WHERE c.id=?`, [uid, uid, uid, id]);
    allMembers.forEach(m => { if (req.io) req.io.to(`user_${m}`).emit('new_conversation', { conversation: conv }); });
    return res.status(201).json({ success: true, conversation: conv });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/messages/conversations/:id/messages
exports.getMessages = async (req, res) => {
  try {
    const uid = req.userId;
    const { id } = req.params;
    const { before_id, limit = 30 } = req.query;
    const member = await db.queryOne('SELECT id FROM conversation_members WHERE conversation_id=? AND user_id=? AND left_at IS NULL', [id, uid]);
    if (!member) return res.status(403).json({ success: false, message: 'Not a member' });

    let sql = `
      SELECT m.*, u.username, u.display_name, u.avatar_url,
        rm.content AS reply_content, rm.type AS reply_type, rmu.display_name AS reply_sender_name,
        rmu.username AS reply_sender_username
      FROM messages m
      JOIN users u ON m.sender_id=u.id
      LEFT JOIN messages rm ON m.reply_to_id=rm.id
      LEFT JOIN users rmu ON rm.sender_id=rmu.id
      WHERE m.conversation_id=? AND m.is_deleted=FALSE
    `;
    const params = [id];
    if (before_id) { sql += ' AND m.id < ?'; params.push(before_id); }
    sql += ' ORDER BY m.created_at DESC LIMIT ?';
    params.push(parseInt(limit));

    let messages = await db.query(sql, params);
    messages.reverse();

    // Load reactions for each message
    for (const msg of messages) {
      msg.reactions = await db.query(
        'SELECT emoji, COUNT(*) AS count, MAX(CASE WHEN user_id=? THEN 1 ELSE 0 END) AS user_reacted FROM message_reactions WHERE message_id=? GROUP BY emoji',
        [uid, msg.id]
      );
      msg.is_edited  = !!msg.is_edited;
      msg.is_deleted = !!msg.is_deleted;
    }

    // Mark read
    if (messages.length) {
      const last = messages[messages.length - 1];
      await db.query('UPDATE conversation_members SET last_read_message_id=? WHERE conversation_id=? AND user_id=?', [last.id, id, uid]);
      if (req.io) req.io.to(`conv_${id}`).emit('messages_read', { reader_id: uid, conversation_id: id });
    }

    res.json({ success: true, messages, has_more: messages.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations/:id/messages
exports.sendMessage = async (req, res) => {
  try {
    const uid  = req.userId;
    const { id } = req.params;
    const { type = 'text', content, reply_to_id, latitude, longitude, contact_name, contact_phone } = req.body;

    const member = await db.queryOne('SELECT id FROM conversation_members WHERE conversation_id=? AND user_id=? AND left_at IS NULL', [id, uid]);
    if (!member) return res.status(403).json({ success: false, message: 'Not a member' });

    let mediaUrl = null, mediaThumbnail = null, mediaSize = null, mediaName = null, mediaDuration = null, mediaMime = null;
    if (req.file) {
      mediaUrl  = getFileUrl(req, req.file.path);
      mediaSize = req.file.size;
      mediaName = req.file.originalname;
      mediaMime = req.file.mimetype;
    }

    const msgId = uuidv4();
    await db.query(`
      INSERT INTO messages (id, conversation_id, sender_id, type, content, media_url, media_thumbnail, media_duration,
        media_size, media_name, media_mime, reply_to_id, latitude, longitude, contact_name, contact_phone)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    `, [msgId, id, uid, type, content || null, mediaUrl, mediaThumbnail, mediaDuration, mediaSize, mediaName, mediaMime, reply_to_id || null, latitude || null, longitude || null, contact_name || null, contact_phone || null]);

    await db.query('UPDATE conversations SET last_message_id=?, last_message_at=NOW() WHERE id=?', [msgId, id]);

    const message = await db.queryOne(`
      SELECT m.*, u.username, u.display_name, u.avatar_url,
        rm.content AS reply_content, rm.type AS reply_type,
        rmu.display_name AS reply_sender_name
      FROM messages m JOIN users u ON m.sender_id=u.id
      LEFT JOIN messages rm ON m.reply_to_id=rm.id
      LEFT JOIN users rmu ON rm.sender_id=rmu.id
      WHERE m.id=?
    `, [msgId]);
    message.reactions = [];
    message.is_edited  = false;
    message.is_deleted = false;

    // Push to members via socket
    if (req.io) {
      const members = await db.query('SELECT user_id FROM conversation_members WHERE conversation_id=? AND left_at IS NULL AND user_id!=?', [id, uid]);
      members.forEach(m => req.io.to(`user_${m.user_id}`).emit('new_message', { conversation_id: id, message }));
      req.io.to(`conv_${id}`).emit('message_sent', { message });
    }

    res.status(201).json({ success: true, message });
  } catch (e) { console.error(e); res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/:msgId/react
exports.reactMessage = async (req, res) => {
  try {
    const { emoji } = req.body;
    if (!emoji) return res.status(400).json({ success: false, message: 'Emoji required' });
    const ex = await db.queryOne('SELECT id, emoji FROM message_reactions WHERE message_id=? AND user_id=?', [req.params.msgId, req.userId]);
    if (ex) {
      if (ex.emoji === emoji) await db.query('DELETE FROM message_reactions WHERE message_id=? AND user_id=?', [req.params.msgId, req.userId]);
      else await db.query('UPDATE message_reactions SET emoji=? WHERE message_id=? AND user_id=?', [emoji, req.params.msgId, req.userId]);
    } else {
      await db.query('INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (?,?,?)', [req.params.msgId, req.userId, emoji]);
    }
    const reactions = await db.query('SELECT emoji, COUNT(*) AS count FROM message_reactions WHERE message_id=? GROUP BY emoji', [req.params.msgId]);
    const msg = await db.queryOne('SELECT conversation_id FROM messages WHERE id=?', [req.params.msgId]);
    if (req.io && msg) req.io.to(`conv_${msg.conversation_id}`).emit('message_reaction', { message_id: req.params.msgId, reactions, actor_id: req.userId });
    res.json({ success: true, reactions });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// DELETE /api/messages/:msgId
exports.deleteMessage = async (req, res) => {
  try {
    const { for_all = false } = req.body;
    const msg = await db.queryOne('SELECT * FROM messages WHERE id=? AND sender_id=?', [req.params.msgId, req.userId]);
    if (!msg) return res.status(404).json({ success: false, message: 'Not found' });
    if (for_all) await db.query('UPDATE messages SET is_deleted=TRUE, deleted_for_all=1, content=NULL, media_url=NULL WHERE id=?', [req.params.msgId]);
    else await db.query('UPDATE messages SET is_deleted=TRUE WHERE id=?', [req.params.msgId]);
    if (req.io) req.io.to(`conv_${msg.conversation_id}`).emit('message_deleted', { message_id: req.params.msgId, for_all, conversation_id: msg.conversation_id });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// PUT /api/messages/:msgId
exports.editMessage = async (req, res) => {
  try {
    const { content } = req.body;
    const msg = await db.queryOne('SELECT * FROM messages WHERE id=? AND sender_id=? AND type=\'text\'', [req.params.msgId, req.userId]);
    if (!msg) return res.status(404).json({ success: false, message: 'Not found' });
    await db.query('UPDATE messages SET content=?, is_edited=TRUE WHERE id=?', [content, req.params.msgId]);
    if (req.io) req.io.to(`conv_${msg.conversation_id}`).emit('message_edited', { message_id: req.params.msgId, content, conversation_id: msg.conversation_id });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/messages/conversations/:id
exports.getConversation = async (req, res) => {
  try {
    const uid = req.userId;
    const { id } = req.params;
    const member = await db.queryOne('SELECT id FROM conversation_members WHERE conversation_id=? AND user_id=? AND left_at IS NULL', [id, uid]);
    if (!member) return res.status(403).json({ success: false, message: 'Not a member' });
    const conv = await db.queryOne(`${convQuery(uid)} WHERE c.id=?`, [uid, uid, uid, id]);
    if (!conv) return res.status(404).json({ success: false });
    res.json({ success: true, conversation: conv });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// PUT /api/messages/conversations/:id (update name/avatar/description)
exports.updateConversation = async (req, res) => {
  try {
    const { name, description } = req.body;
    await db.query('UPDATE conversations SET name=COALESCE(?,name), description=COALESCE(?,description) WHERE id=?', [name || null, description || null, req.params.id]);
    if (req.io) req.io.to(`conv_${req.params.id}`).emit('conversation_updated', { conversation_id: req.params.id, name, description });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/messages/conversations/:id/media
exports.getMedia = async (req, res) => {
  try {
    const { type } = req.query;
    let typeCond = '';
    if (type === 'media') typeCond = "AND m.type IN ('image','video')";
    else if (type === 'files') typeCond = "AND m.type = 'file'";
    else if (type === 'audio') typeCond = "AND m.type IN ('audio','voice_note')";
    const msgs = await db.query(`SELECT m.* FROM messages m WHERE m.conversation_id=? AND m.is_deleted=FALSE ${typeCond} ORDER BY m.created_at DESC LIMIT 200`, [req.params.id]);
    res.json({ success: true, messages: msgs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/messages/conversations/:id/pinned
exports.getPinned = async (req, res) => {
  try {
    const msgs = await db.query(`SELECT m.*, u.username, u.display_name, u.avatar_url FROM pinned_messages pm JOIN messages m ON pm.message_id=m.id JOIN users u ON m.sender_id=u.id WHERE pm.conversation_id=? ORDER BY pm.pinned_at DESC`, [req.params.id]);
    res.json({ success: true, messages: msgs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations/:id/members
exports.addMembers = async (req, res) => {
  try {
    const { user_ids = [] } = req.body;
    for (const uid of user_ids) {
      const ex = await db.queryOne('SELECT id, left_at FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, uid]);
      if (ex && ex.left_at) await db.query('UPDATE conversation_members SET left_at=NULL, joined_at=NOW() WHERE id=?', [ex.id]);
      else if (!ex) await db.query('INSERT INTO conversation_members (conversation_id, user_id) VALUES (?,?)', [req.params.id, uid]);
    }
    if (req.io) user_ids.forEach(uid => req.io.to(`user_${uid}`).emit('added_to_group', { conversation_id: req.params.id }));
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// DELETE /api/messages/conversations/:id/members/:uid
exports.removeMember = async (req, res) => {
  try {
    await db.query('UPDATE conversation_members SET left_at=NOW() WHERE conversation_id=? AND user_id=?', [req.params.id, req.params.uid]);
    if (req.io) req.io.to(`conv_${req.params.id}`).emit('member_left', { conversation_id: req.params.id, user_id: req.params.uid });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations/:id/mute
exports.muteConversation = async (req, res) => {
  try {
    const { duration_hours } = req.body;
    const muteUntil = duration_hours ? new Date(Date.now() + duration_hours * 3600000) : null;
    await db.query('UPDATE conversation_members SET muted_until=? WHERE conversation_id=? AND user_id=?', [muteUntil, req.params.id, req.userId]);
    res.json({ success: true, muted_until: muteUntil });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations/:id/archive
exports.archiveConversation = async (req, res) => {
  try {
    const { archived = true } = req.body;
    await db.query('UPDATE conversation_members SET is_archived=? WHERE conversation_id=? AND user_id=?', [archived ? 1 : 0, req.params.id, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/conversations/:id/pin (pin conversation to top)
exports.pinConversation = async (req, res) => {
  try {
    const cur = await db.queryOne('SELECT is_pinned FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    await db.query('UPDATE conversation_members SET is_pinned=? WHERE conversation_id=? AND user_id=?', [cur?.is_pinned ? 0 : 1, req.params.id, req.userId]);
    res.json({ success: true, pinned: !cur?.is_pinned });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/messages/:msgId/forward
exports.forwardMessage = async (req, res) => {
  try {
    const { v4: uuidv4 } = require('uuid');
    const { conversation_ids = [] } = req.body;
    const orig = await db.queryOne('SELECT * FROM messages WHERE id=?', [req.params.msgId]);
    if (!orig) return res.status(404).json({ success: false });
    for (const convId of conversation_ids) {
      const newId = uuidv4();
      await db.query('INSERT INTO messages (id,conversation_id,sender_id,type,content,media_url,media_thumbnail,media_name,media_mime,media_duration,media_size,is_forwarded) VALUES (?,?,?,?,?,?,?,?,?,?,?,1)',
        [newId, convId, req.userId, orig.type, orig.content, orig.media_url, orig.media_thumbnail, orig.media_name, orig.media_mime, orig.media_duration, orig.media_size]);
      await db.query('UPDATE conversations SET last_message_id=?, last_message_at=NOW() WHERE id=?', [newId, convId]);
      if (req.io) req.io.to(`conv_${convId}`).emit('new_message', { message: { id: newId, conversation_id: convId, sender_id: req.userId, type: orig.type, content: orig.content, media_url: orig.media_url, is_forwarded: true, created_at: new Date().toISOString() } });
    }
    res.json({ success: true, forwarded_to: conversation_ids.length });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};
