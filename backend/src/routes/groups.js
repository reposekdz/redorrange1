// routes/groups.js - Group management
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const db = require('../config/database');
const { notify } = require('../services/notificationService');

// GET /api/groups/:id - Get group info
r.get('/:id', authenticate, async (req, res) => {
  try {
    const conv = await db.queryOne('SELECT * FROM conversations WHERE id=? AND type="group"', [req.params.id]);
    if (!conv) return res.status(404).json({ success: false, message: 'Group not found' });

    const members = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified, u.is_online, cm.role, cm.joined_at
      FROM conversation_members cm JOIN users u ON cm.user_id=u.id
      WHERE cm.conversation_id=? AND cm.left_at IS NULL
      ORDER BY cm.role='owner' DESC, cm.role='admin' DESC, cm.joined_at ASC
    `, [req.params.id]);

    members.forEach(m => { m.is_online = !!m.is_online; m.is_verified = !!m.is_verified; });
    res.json({ success: true, group: conv, members });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// PUT /api/groups/:id - Update group info
r.put('/:id', authenticate, upload.single('avatar'), async (req, res) => {
  try {
    const { name, description } = req.body;
    const mem = await db.queryOne('SELECT role FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    if (!mem || !['owner','admin'].includes(mem.role)) return res.status(403).json({ success: false, message: 'Not authorized' });
    const fields = {};
    if (name) fields.name = name;
    if (description !== undefined) fields.description = description;
    if (req.file) fields.avatar_url = getFileUrl(req, req.file.path);
    if (Object.keys(fields).length) {
      const sets = Object.keys(fields).map(k => `${k}=?`).join(', ');
      await db.query(`UPDATE conversations SET ${sets} WHERE id=?`, [...Object.values(fields), req.params.id]);
    }
    const group = await db.queryOne('SELECT * FROM conversations WHERE id=?', [req.params.id]);
    if (req.io) {
      const members = await db.query('SELECT user_id FROM conversation_members WHERE conversation_id=? AND left_at IS NULL', [req.params.id]);
      members.forEach(m => req.io.to(`user_${m.user_id}`).emit('group_updated', { group }));
    }
    res.json({ success: true, group });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/groups/:id/add-members
r.post('/:id/add-members', authenticate, async (req, res) => {
  try {
    const { user_ids } = req.body;
    const mem = await db.queryOne('SELECT role FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    if (!mem || !['owner','admin'].includes(mem.role)) return res.status(403).json({ success: false, message: 'Not authorized' });
    const ids = Array.isArray(user_ids) ? user_ids : [user_ids];
    for (const uid of ids) {
      const ex = await db.queryOne('SELECT id FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, uid]);
      if (ex) await db.query('UPDATE conversation_members SET left_at=NULL WHERE conversation_id=? AND user_id=?', [req.params.id, uid]);
      else await db.query('INSERT INTO conversation_members (conversation_id, user_id) VALUES (?,?)', [req.params.id, uid]);
      if (req.io) req.io.to(`user_${uid}`).emit('added_to_group', { conversation_id: req.params.id });
    }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// DELETE /api/groups/:id/remove/:userId
r.delete('/:id/remove/:userId', authenticate, async (req, res) => {
  try {
    const mem = await db.queryOne('SELECT role FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    if (!mem || !['owner','admin'].includes(mem.role)) return res.status(403).json({ success: false, message: 'Not authorized' });
    await db.query('UPDATE conversation_members SET left_at=NOW() WHERE conversation_id=? AND user_id=?', [req.params.id, req.params.userId]);
    if (req.io) req.io.to(`user_${req.params.userId}`).emit('removed_from_group', { conversation_id: req.params.id });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/groups/:id/leave
r.post('/:id/leave', authenticate, async (req, res) => {
  try {
    await db.query('UPDATE conversation_members SET left_at=NOW() WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    const actor = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    // Notify remaining members
    const msg = await db.queryOne('INSERT INTO messages (id, conversation_id, sender_id, type, content) VALUES (UUID(),?,?,"text",?) RETURNING *',
      [req.params.id, req.userId, `${actor?.display_name || actor?.username} left the group`]);
    if (req.io) {
      const remaining = await db.query('SELECT user_id FROM conversation_members WHERE conversation_id=? AND left_at IS NULL', [req.params.id]);
      remaining.forEach(m => req.io.to(`user_${m.user_id}`).emit('member_left', { conversation_id: req.params.id, user_id: req.userId }));
    }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// PUT /api/groups/:id/promote/:userId
r.put('/:id/promote/:userId', authenticate, async (req, res) => {
  try {
    const { role = 'admin' } = req.body;
    const mem = await db.queryOne('SELECT role FROM conversation_members WHERE conversation_id=? AND user_id=?', [req.params.id, req.userId]);
    if (mem?.role !== 'owner') return res.status(403).json({ success: false, message: 'Only owner can promote' });
    await db.query('UPDATE conversation_members SET role=? WHERE conversation_id=? AND user_id=?', [role, req.params.id, req.params.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
