// routes/events.js
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const { notify } = require('../services/notificationService');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

r.get('/', authenticate, async (req, res) => {
  try {
    const { page = 1, limit = 10, filter = 'upcoming' } = req.query;
    const offset = (page - 1) * limit;
    const where  = filter === 'past' ? 'e.start_datetime <= NOW()' : 'e.start_datetime > NOW()';
    const events = await db.query(`
      SELECT e.*, u.username, u.display_name, u.avatar_url,
        (SELECT status FROM event_attendees WHERE event_id=e.id AND user_id=?) AS my_status
      FROM events e JOIN users u ON e.creator_id=u.id
      WHERE ${where} AND e.event_type='public'
      ORDER BY e.start_datetime ASC LIMIT ? OFFSET ?
    `, [req.userId, parseInt(limit), parseInt(offset)]);
    res.json({ success: true, events });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/', authenticate, upload.single('event_cover'), async (req, res) => {
  try {
    const { title, description, event_type = 'public', start_datetime, end_datetime, location, lat, lng, online_link, max_attendees } = req.body;
    if (!title || !start_datetime) return res.status(400).json({ success: false, message: 'Title and start date required' });
    const id = uuidv4();
    const coverUrl = req.file ? getFileUrl(req, req.file.path) : null;
    await db.query(
      'INSERT INTO events (id, creator_id, title, description, cover_url, event_type, start_datetime, end_datetime, location, lat, lng, online_link, max_attendees) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [id, req.userId, title, description || null, coverUrl, event_type, start_datetime, end_datetime || null, location || null, lat || null, lng || null, online_link || null, max_attendees || null]
    );
    await db.query('INSERT INTO event_attendees (event_id, user_id, status) VALUES (?,?,?)', [id, req.userId, 'going']);
    await db.query('UPDATE events SET going_count=1 WHERE id=?', [id]);
    const event = await db.queryOne('SELECT e.*, u.username, u.display_name, u.avatar_url FROM events e JOIN users u ON e.creator_id=u.id WHERE e.id=?', [id]);
    res.status(201).json({ success: true, event });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:id', authenticate, async (req, res) => {
  try {
    const event = await db.queryOne(`
      SELECT e.*, u.username, u.display_name, u.avatar_url,
        (SELECT status FROM event_attendees WHERE event_id=e.id AND user_id=?) AS my_status
      FROM events e JOIN users u ON e.creator_id=u.id WHERE e.id=?
    `, [req.userId, req.params.id]);
    if (!event) return res.status(404).json({ success: false, message: 'Not found' });
    res.json({ success: true, event });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.put('/:id', authenticate, upload.single('event_cover'), async (req, res) => {
  try {
    const ev = await db.queryOne('SELECT id FROM events WHERE id=? AND creator_id=?', [req.params.id, req.userId]);
    if (!ev) return res.status(403).json({ success: false, message: 'Not authorized' });
    const { title, description, start_datetime, end_datetime, location, online_link } = req.body;
    const fields = {};
    if (title          ) fields.title           = title;
    if (description    ) fields.description     = description;
    if (start_datetime ) fields.start_datetime  = start_datetime;
    if (end_datetime   ) fields.end_datetime    = end_datetime;
    if (location       ) fields.location        = location;
    if (online_link    ) fields.online_link     = online_link;
    if (req.file       ) fields.cover_url       = getFileUrl(req, req.file.path);
    const sets = Object.keys(fields).map(k => `${k}=?`).join(', ');
    await db.query(`UPDATE events SET ${sets}, updated_at=NOW() WHERE id=?`, [...Object.values(fields), req.params.id]);
    const event = await db.queryOne('SELECT * FROM events WHERE id=?', [req.params.id]);
    res.json({ success: true, event });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM events WHERE id=? AND creator_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

r.post('/:id/attend', authenticate, async (req, res) => {
  try {
    const { status } = req.body;
    if (!['going','interested','not_going'].includes(status)) return res.status(400).json({ success: false, message: 'Invalid status' });
    const ex = await db.queryOne('SELECT id, status AS old_status FROM event_attendees WHERE event_id=? AND user_id=?', [req.params.id, req.userId]);
    if (ex) {
      if (ex.old_status === 'going')      await db.query('UPDATE events SET going_count=GREATEST(0,going_count-1) WHERE id=?', [req.params.id]);
      if (ex.old_status === 'interested') await db.query('UPDATE events SET interested_count=GREATEST(0,interested_count-1) WHERE id=?', [req.params.id]);
      await db.query('UPDATE event_attendees SET status=? WHERE event_id=? AND user_id=?', [status, req.params.id, req.userId]);
    } else {
      await db.query('INSERT INTO event_attendees (event_id, user_id, status) VALUES (?,?,?)', [req.params.id, req.userId, status]);
    }
    if (status === 'going')      await db.query('UPDATE events SET going_count=going_count+1 WHERE id=?',      [req.params.id]);
    if (status === 'interested') await db.query('UPDATE events SET interested_count=interested_count+1 WHERE id=?', [req.params.id]);
    res.json({ success: true, status });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:id/attendees', authenticate, async (req, res) => {
  const attendees = await db.query(`
    SELECT ea.status, u.id, u.username, u.display_name, u.avatar_url
    FROM event_attendees ea JOIN users u ON ea.user_id=u.id
    WHERE ea.event_id=? ORDER BY ea.created_at ASC
  `, [req.params.id]);
  res.json({ success: true, attendees });
});

module.exports = r;
