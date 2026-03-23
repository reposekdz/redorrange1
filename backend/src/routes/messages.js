const express    = require('express');
const r          = express.Router();
const c          = require('../controllers/messagesController');
const { authenticate } = require('../middleware/auth');
const { upload } = require('../middleware/upload');
const db         = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// Conversations
r.get('/conversations',                    authenticate, c.getConversations);
r.post('/conversations',                   authenticate, upload.single('avatar'), c.createConversation);
r.get('/conversations/:id',                authenticate, c.getConversation);
r.put('/conversations/:id',                authenticate, c.updateConversation);
r.get('/conversations/:id/messages',       authenticate, c.getMessages);
r.post('/conversations/:id/messages',      authenticate, upload.single('message_file'), c.sendMessage);
r.get('/conversations/:id/media',          authenticate, c.getMedia);
r.get('/conversations/:id/pinned',         authenticate, c.getPinned);
r.post('/conversations/:id/members',       authenticate, c.addMembers);
r.delete('/conversations/:id/members/:uid',authenticate, c.removeMember);
r.post('/conversations/:id/mute',          authenticate, c.muteConversation);
r.post('/conversations/:id/archive',       authenticate, c.archiveConversation);
r.post('/conversations/:id/pin',           authenticate, c.pinConversation);

// Messages
r.post('/:msgId/react',                    authenticate, c.reactMessage);
r.delete('/:msgId',                        authenticate, c.deleteMessage);
r.put('/:msgId',                           authenticate, c.editMessage);
r.post('/:msgId/forward',                  authenticate, c.forwardMessage);

// Smart replies
r.get('/:id/smart-replies', authenticate, async (req, res) => {
  try {
    const msg = await db.queryOne('SELECT content, type FROM messages WHERE id=?', [req.params.id]);
    if (!msg || msg.type !== 'text' || !msg.content) return res.json({ success: true, suggestions: [] });
    const t = msg.content.toLowerCase().trim();
    let s = ['👍', 'Got it!', 'OK sure'];
    if (/how are you|how r u/.test(t))     s = ["I'm doing great!", 'Pretty good, you?', 'All good! 😊'];
    else if (/thank|thanks|thx/.test(t))   s = ["You're welcome!", 'No problem!', 'Anytime!'];
    else if (/hello|hi|hey|sup/.test(t))   s = ['Hey! 👋', 'Hello!', 'Hi there!'];
    else if (/ok|okay|sure/.test(t))       s = ['Sounds good!', 'Perfect! ✅', 'Got it'];
    else if (/when|what time/.test(t))     s = ['Let me check', 'Around 3pm?', 'What time works?'];
    else if (/love|miss/.test(t))          s = ['❤️', 'Miss you too!', '😊'];
    else if (t.includes('?'))              s = ['Yes', 'No', 'Let me check'];
    res.json({ success: true, suggestions: s });
  } catch (e) { res.status(500).json({ success: false, suggestions: [] }); }
});

// Scheduled
r.post('/conversations/:id/schedule', authenticate, async (req, res) => {
  try {
    const { content, type = 'text', scheduled_at } = req.body;
    if (!content || !scheduled_at) return res.status(400).json({ success: false, message: 'content and scheduled_at required' });
    const id = uuidv4();
    await db.query('INSERT INTO scheduled_messages (id, conversation_id, sender_id, type, content, scheduled_at) VALUES (?,?,?,?,?,?)', [id, req.params.id, req.userId, type, content, scheduled_at]);
    res.status(201).json({ success: true, id, scheduled_at });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/conversations/:id/scheduled', authenticate, async (req, res) => {
  try {
    const msgs = await db.query("SELECT * FROM scheduled_messages WHERE conversation_id=? AND sender_id=? AND status='pending' ORDER BY scheduled_at", [req.params.id, req.userId]);
    res.json({ success: true, scheduled: msgs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/conversations/:id/scheduled/:mid', authenticate, async (req, res) => {
  await db.query("UPDATE scheduled_messages SET status='cancelled' WHERE id=? AND sender_id=?", [req.params.mid, req.userId]);
  res.json({ success: true });
});

// Disappearing
r.put('/conversations/:id/disappearing', authenticate, async (req, res) => {
  try {
    const { timer = 0 } = req.body;
    await db.query('UPDATE conversation_members SET disappearing_timer=? WHERE conversation_id=? AND user_id=?', [parseInt(timer), req.params.id, req.userId]);
    await db.query('UPDATE conversations SET disappearing_timer=? WHERE id=?', [parseInt(timer), req.params.id]);
    const members = await db.query('SELECT user_id FROM conversation_members WHERE conversation_id=? AND left_at IS NULL', [req.params.id]);
    if (req.io) members.forEach(m => req.io.to(`user_${m.user_id}`).emit('disappearing_changed', { conversation_id: req.params.id, timer: parseInt(timer) }));
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
