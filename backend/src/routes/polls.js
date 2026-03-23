// routes/polls.js
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

r.post('/post/:postId', authenticate, async (req, res) => {
  try {
    const { question, options, expires_hours = 24, multiple = false } = req.body;
    if (!question || !options || options.length < 2) return res.status(400).json({ success: false, message: 'Question and at least 2 options required' });
    const pollId = uuidv4();
    const expiresAt = new Date(Date.now() + (parseInt(expires_hours) || 24) * 3600000);
    await db.query('INSERT INTO polls (id, post_id, question, expires_at, multiple) VALUES (?,?,?,?,?)',
      [pollId, req.params.postId, question, expiresAt, multiple ? 1 : 0]);
    for (let i = 0; i < options.length; i++) {
      await db.query('INSERT INTO poll_options (poll_id, text, order_idx) VALUES (?,?,?)', [pollId, options[i], i]);
    }
    const poll = await db.queryOne('SELECT * FROM polls WHERE id=?', [pollId]);
    poll.options = await db.query('SELECT * FROM poll_options WHERE poll_id=? ORDER BY order_idx', [pollId]);
    res.status(201).json({ success: true, poll });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:pollId', authenticate, async (req, res) => {
  try {
    const poll = await db.queryOne('SELECT * FROM polls WHERE id=?', [req.params.pollId]);
    if (!poll) return res.status(404).json({ success: false, message: 'Poll not found' });
    poll.options = await db.query(`
      SELECT po.*, (SELECT COUNT(*) > 0 FROM poll_votes WHERE option_id=po.id AND user_id=?) AS user_voted
      FROM poll_options po WHERE po.poll_id=? ORDER BY po.order_idx
    `, [req.userId, req.params.pollId]);
    poll.total_votes = poll.options.reduce((s, o) => s + (o.votes || 0), 0);
    poll.user_voted = poll.options.some(o => o.user_voted);
    res.json({ success: true, poll });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/:pollId/vote', authenticate, async (req, res) => {
  try {
    const { option_ids } = req.body;
    const ids = Array.isArray(option_ids) ? option_ids : [option_ids];
    const poll = await db.queryOne('SELECT * FROM polls WHERE id=?', [req.params.pollId]);
    if (!poll) return res.status(404).json({ success: false, message: 'Not found' });
    if (poll.expires_at && new Date() > new Date(poll.expires_at)) return res.status(400).json({ success: false, message: 'Poll has expired' });
    const existing = await db.queryOne('SELECT id FROM poll_votes WHERE poll_id=? AND user_id=?', [req.params.pollId, req.userId]);
    if (existing && !poll.multiple) return res.status(400).json({ success: false, message: 'Already voted' });
    for (const oid of ids) {
      await db.query('INSERT INTO poll_votes (poll_id, option_id, user_id) VALUES (?,?,?)', [req.params.pollId, oid, req.userId]);
      await db.query('UPDATE poll_options SET votes=votes+1 WHERE id=?', [oid]);
    }
    const options = await db.query('SELECT id, text, votes FROM poll_options WHERE poll_id=? ORDER BY order_idx', [req.params.pollId]);
    if (req.io) req.io.to(`poll_${req.params.pollId}`).emit('poll_vote', { poll_id: req.params.pollId, options });
    res.json({ success: true, options });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
