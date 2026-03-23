const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');

r.get('/', authenticate, async (req, res) => {
  try {
    const uid = req.userId;
    const calls = await db.query(`
      SELECT c.*,
        CASE WHEN c.caller_id=? THEN 'outgoing' ELSE 'incoming' END AS direction,
        CASE WHEN c.caller_id=? THEN c.callee_id ELSE c.caller_id END AS other_id,
        CASE WHEN c.caller_id=? THEN cu.username ELSE u.username END AS other_username,
        CASE WHEN c.caller_id=? THEN cu.display_name ELSE u.display_name END AS other_display_name,
        CASE WHEN c.caller_id=? THEN cu.avatar_url ELSE u.avatar_url END AS avatar_url
      FROM calls c
      LEFT JOIN users u ON c.caller_id=u.id
      LEFT JOIN users cu ON c.callee_id=cu.id
      WHERE c.caller_id=? OR c.callee_id=?
      ORDER BY c.created_at DESC LIMIT 100
    `, [uid, uid, uid, uid, uid, uid, uid]);
    res.json({ success: true, calls });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM calls WHERE id=? AND (caller_id=? OR callee_id=?)', [req.params.id, req.userId, req.userId]);
  res.json({ success: true });
});

r.delete('/', authenticate, async (req, res) => {
  await db.query('DELETE FROM calls WHERE caller_id=? OR callee_id=?', [req.userId, req.userId]);
  res.json({ success: true });
});

module.exports = r;
