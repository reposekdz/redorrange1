const db = require('../config/database');
const { notify } = require('../services/notificationService');

// POST /api/contacts/lookup - check if phone exists
exports.lookupPhone = async (req, res) => {
  try {
    const { phone_number, country_code = '+1' } = req.body;
    if (!phone_number) return res.status(400).json({ success: false, message: 'Phone required' });

    const full = `${country_code}${phone_number.replace(/\D/g,'')}`;
    const user = await db.queryOne(
      'SELECT id, username, display_name, avatar_url, is_verified, status_text FROM users WHERE phone_number=?',
      [full]
    );

    if (!user) return res.json({ success: true, exists: false, message: 'No account found with this number' });

    if (user.id === req.userId) return res.json({ success: true, exists: true, is_self: true });

    // Check if already contact
    const existing = await db.queryOne('SELECT id FROM contacts WHERE user_id=? AND contact_id=?', [req.userId, user.id]);
    res.json({
      success: true,
      exists: true,
      user: { id: user.id, username: user.username, display_name: user.display_name, avatar_url: user.avatar_url, is_verified: !!user.is_verified, status_text: user.status_text },
      already_contact: !!existing,
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// POST /api/contacts/add
exports.addContact = async (req, res) => {
  try {
    const { contact_id, nickname } = req.body;
    if (!contact_id) return res.status(400).json({ success: false, message: 'Contact ID required' });
    if (contact_id === req.userId) return res.status(400).json({ success: false, message: 'Cannot add yourself' });

    const target = await db.queryOne('SELECT id, display_name, username FROM users WHERE id=?', [contact_id]);
    if (!target) return res.status(404).json({ success: false, message: 'User not found' });

    const existing = await db.queryOne('SELECT id FROM contacts WHERE user_id=? AND contact_id=?', [req.userId, contact_id]);
    if (existing) return res.json({ success: true, already_exists: true });

    await db.query('INSERT INTO contacts (user_id, contact_id, nickname) VALUES (?,?,?)', [req.userId, contact_id, nickname || null]);

    const me = await db.queryOne('SELECT display_name, username FROM users WHERE id=?', [req.userId]);
    await notify(req.io, {
      userId: contact_id, actorId: req.userId,
      type: 'contact_joined',
      message: `${me?.display_name || me?.username} added you as a contact`,
    });

    res.json({ success: true, message: 'Contact added' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/contacts
exports.getContacts = async (req, res) => {
  try {
    const { q } = req.query;
    let sql = `
      SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified, u.is_online, u.last_seen, u.status_text,
        c.nickname,
        (SELECT COUNT(*) > 0 FROM blocks WHERE blocker_id=? AND blocked_id=u.id) AS is_blocked
      FROM contacts c JOIN users u ON c.contact_id=u.id
      WHERE c.user_id=?
    `;
    const params = [req.userId, req.userId];
    if (q) { sql += ' AND (u.display_name LIKE ? OR u.username LIKE ? OR c.nickname LIKE ?)'; params.push(`%${q}%`, `%${q}%`, `%${q}%`); }
    sql += ' ORDER BY u.display_name ASC';

    const contacts = await db.query(sql, params);
    contacts.forEach(c => { c.is_verified = !!c.is_verified; c.is_online = !!c.is_online; c.is_blocked = !!c.is_blocked; });
    res.json({ success: true, contacts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// DELETE /api/contacts/:id
exports.removeContact = async (req, res) => {
  await db.query('DELETE FROM contacts WHERE user_id=? AND contact_id=?', [req.userId, req.params.id]);
  res.json({ success: true });
};

// PUT /api/contacts/:id/nickname
exports.setNickname = async (req, res) => {
  await db.query('UPDATE contacts SET nickname=? WHERE user_id=? AND contact_id=?', [req.body.nickname, req.userId, req.params.id]);
  res.json({ success: true });
};

// POST /api/contacts/:id/block
exports.blockContact = async (req, res) => {
  try {
    await db.query('INSERT INTO blocks (blocker_id, blocked_id) VALUES (?,?) ON CONFLICT DO NOTHING', [req.userId, req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};
