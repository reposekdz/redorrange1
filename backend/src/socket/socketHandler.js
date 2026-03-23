const jwt     = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db      = require('../config/database');
const { notify } = require('../services/notificationService');

// In-memory presence (use Redis in production for multi-instance)
const onlineUsers = new Map(); // userId → Set<socketId>
const typingTimers = new Map(); // convId:userId → timeout

function addOnline(uid, sid)  { if (!onlineUsers.has(uid)) onlineUsers.set(uid, new Set()); onlineUsers.get(uid).add(sid); }
function removeOnline(uid, sid) { onlineUsers.get(uid)?.delete(sid); if (onlineUsers.get(uid)?.size === 0) onlineUsers.delete(uid); }
function isOnline(uid) { return (onlineUsers.get(uid)?.size ?? 0) > 0; }

module.exports = (io) => {

  // ── JWT Auth middleware
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) return next(new Error('AUTH_REQUIRED'));
      const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
      const user = await db.queryOne(
        'SELECT id, username, display_name, avatar_url, is_verified, status_text FROM users WHERE id=?',
        [decoded.userId]
      );
      if (!user) return next(new Error('USER_NOT_FOUND'));
      socket.userId = user.id;
      socket.user   = user;
      next();
    } catch (e) { next(new Error('AUTH_FAILED')); }
  });

  io.on('connection', async (socket) => {
    const uid = socket.userId;

    // ── Online tracking
    addOnline(uid, socket.id);
    socket.join(`user_${uid}`);
    await db.query('UPDATE users SET is_online=1, last_seen=NOW() WHERE id=?', [uid]);

    // Auto-join all conversation rooms
    try {
      const convs = await db.query(
        'SELECT conversation_id FROM conversation_members WHERE user_id=? AND left_at IS NULL',
        [uid]
      );
      for (const c of convs) socket.join(`conv_${c.conversation_id}`);
    } catch {}

    // Notify contacts of coming online
    _broadcastPresence(io, uid, socket.user, true);

    // ════════════════════════════════════════════════════════
    // MESSAGING EVENTS
    // ════════════════════════════════════════════════════════
    socket.on('join_conversation',  ({ conversation_id }) => socket.join(`conv_${conversation_id}`));
    socket.on('leave_conversation', ({ conversation_id }) => socket.leave(`conv_${conversation_id}`));

    socket.on('typing_start', ({ conversation_id }) => {
      const key = `${conversation_id}:${uid}`;
      if (typingTimers.has(key)) clearTimeout(typingTimers.get(key));
      socket.to(`conv_${conversation_id}`).emit('user_typing', {
        user_id: uid, conversation_id,
        display_name: socket.user.display_name,
        avatar_url:   socket.user.avatar_url,
      });
      // Auto stop after 4s
      typingTimers.set(key, setTimeout(() => {
        socket.to(`conv_${conversation_id}`).emit('user_stopped_typing', { user_id: uid, conversation_id });
        typingTimers.delete(key);
      }, 4000));
    });

    socket.on('typing_stop', ({ conversation_id }) => {
      const key = `${conversation_id}:${uid}`;
      clearTimeout(typingTimers.get(key));
      typingTimers.delete(key);
      socket.to(`conv_${conversation_id}`).emit('user_stopped_typing', { user_id: uid, conversation_id });
    });

    socket.on('mark_read', async ({ conversation_id }) => {
      try {
        const last = await db.queryOne(
          'SELECT id FROM messages WHERE conversation_id=? AND is_deleted=0 ORDER BY created_at DESC LIMIT 1',
          [conversation_id]
        );
        if (last) {
          await db.query(
            'UPDATE conversation_members SET last_read_message_id=?, unread_count=0 WHERE conversation_id=? AND user_id=?',
            [last.id, conversation_id, uid]
          );
          // Update message status to seen for all messages from others
          await db.query(
            "UPDATE messages SET status='seen' WHERE conversation_id=? AND sender_id!=? AND status!='seen'",
            [conversation_id, uid]
          );
        }
        socket.to(`conv_${conversation_id}`).emit('messages_read', {
          reader_id: uid, conversation_id,
          reader_name: socket.user.display_name,
          reader_avatar: socket.user.avatar_url,
        });
      } catch (e) { console.error('[mark_read]', e.message); }
    });

    socket.on('message_delivered', async ({ message_id, sender_id, conversation_id }) => {
      try {
        await db.query("UPDATE messages SET status='delivered' WHERE id=? AND status='sent'", [message_id]);
        io.to(`user_${sender_id}`).emit('message_status_update', {
          message_id, status: 'delivered', conversation_id, user_id: uid,
        });
      } catch {}
    });

    socket.on('message_reaction', async ({ message_id, emoji, conversation_id }) => {
      try {
        const ex = await db.queryOne(
          'SELECT id FROM message_reactions WHERE message_id=? AND user_id=? AND emoji=?',
          [message_id, uid, emoji]
        );
        if (ex) {
          await db.query('DELETE FROM message_reactions WHERE id=?', [ex.id]);
        } else {
          await db.query('INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (?,?,?)', [message_id, uid, emoji]);
          const msg = await db.queryOne('SELECT sender_id FROM messages WHERE id=?', [message_id]);
          if (msg && msg.sender_id !== uid) {
            await notify(io, {
              userId: msg.sender_id, actorId: uid, type: 'message_reaction',
              targetType: 'message', targetId: message_id,
              message: `${socket.user.display_name || socket.user.username} reacted ${emoji} to your message`,
            });
          }
        }
        const reactions = await db.query(
          'SELECT emoji, COUNT(*) AS count, GROUP_CONCAT(user_id) AS user_ids FROM message_reactions WHERE message_id=? GROUP BY emoji',
          [message_id]
        );
        io.to(`conv_${conversation_id}`).emit('message_reaction', { message_id, reactions, conversation_id });
      } catch (e) { console.error('[reaction]', e.message); }
    });

    socket.on('star_message', async ({ message_id }) => {
      try {
        const ex = await db.queryOne('SELECT id FROM starred_messages WHERE user_id=? AND message_id=?', [uid, message_id]);
        if (ex) await db.query('DELETE FROM starred_messages WHERE id=?', [ex.id]);
        else     await db.query('INSERT INTO starred_messages (user_id, message_id) VALUES (?,?)', [uid, message_id]);
        socket.emit('message_starred', { message_id, starred: !ex });
      } catch {}
    });

    socket.on('pin_message', async ({ message_id, conversation_id }) => {
      try {
        const ex = await db.queryOne('SELECT id FROM pinned_messages WHERE conversation_id=? AND message_id=?', [conversation_id, message_id]);
        if (ex) {
          await db.query('DELETE FROM pinned_messages WHERE id=?', [ex.id]);
          io.to(`conv_${conversation_id}`).emit('message_unpinned', { message_id, conversation_id });
        } else {
          await db.query('INSERT INTO pinned_messages (conversation_id, message_id, pinned_by) VALUES (?,?,?)', [conversation_id, message_id, uid]);
          const msg = await db.queryOne('SELECT content, type FROM messages WHERE id=?', [message_id]);
          io.to(`conv_${conversation_id}`).emit('message_pinned', { message_id, conversation_id, content: msg?.content, type: msg?.type, pinned_by: uid });
        }
      } catch (e) { console.error('[pin]', e.message); }
    });

    // ════════════════════════════════════════════════════════
    // WEBRTC CALLS
    // ════════════════════════════════════════════════════════
    socket.on('call_initiate', async ({ callee_id, call_type, offer }) => {
      try {
        // Check if callee is online
        if (!isOnline(callee_id)) {
          socket.emit('call_unavailable', { reason: 'User is offline', callee_id });
          return;
        }
        const callId = uuidv4();
        await db.query(
          'INSERT INTO calls (id, caller_id, callee_id, type, status) VALUES (?,?,?,?,?)',
          [callId, uid, callee_id, call_type, 'ringing']
        );
        io.to(`user_${callee_id}`).emit('incoming_call', {
          call_id: callId, caller: socket.user,
          call_type, offer, started_at: new Date().toISOString(),
        });
        socket.emit('call_initiated', { call_id: callId, callee_id });
        await notify(io, {
          userId: callee_id, actorId: uid, type: 'call',
          targetType: 'call', targetId: callId,
          message: `Incoming ${call_type} call from ${socket.user.display_name || socket.user.username}`,
        });
      } catch (e) { console.error('[call_initiate]', e.message); }
    });

    socket.on('call_answer', async ({ call_id, caller_id, answer }) => {
      try {
        await db.query("UPDATE calls SET status='answered', answered_at=NOW() WHERE id=?", [call_id]);
        io.to(`user_${caller_id}`).emit('call_answered', { call_id, answer, callee: socket.user });
      } catch {}
    });

    socket.on('call_reject', async ({ call_id, caller_id, reason }) => {
      try {
        await db.query("UPDATE calls SET status='rejected', ended_at=NOW() WHERE id=?", [call_id]);
        io.to(`user_${caller_id}`).emit('call_rejected', { call_id, reason: reason || 'declined', callee: socket.user });
      } catch {}
    });

    socket.on('call_end', async ({ call_id, other_user_id, duration }) => {
      try {
        await db.query("UPDATE calls SET status='ended', ended_at=NOW(), duration=? WHERE id=?", [duration || 0, call_id]);
        io.to(`user_${other_user_id}`).emit('call_ended', { call_id, duration, ended_by: uid });
      } catch {}
    });

    socket.on('call_busy', ({ caller_id, call_id }) => {
      io.to(`user_${caller_id}`).emit('call_busy', { call_id, callee: socket.user });
    });

    socket.on('ice_candidate', ({ target_user_id, candidate, call_id }) => {
      io.to(`user_${target_user_id}`).emit('ice_candidate', { candidate, call_id, from_user_id: uid });
    });

    socket.on('call_toggle_video', ({ call_id, enabled, other_user_id }) => {
      io.to(`user_${other_user_id}`).emit('remote_video_toggle', { call_id, enabled, user_id: uid });
    });

    socket.on('call_toggle_audio', ({ call_id, enabled, other_user_id }) => {
      io.to(`user_${other_user_id}`).emit('remote_audio_toggle', { call_id, enabled, user_id: uid });
    });

    socket.on('call_screen_share', ({ call_id, enabled, other_user_id }) => {
      io.to(`user_${other_user_id}`).emit('remote_screen_share', { call_id, enabled, user_id: uid });
    });

    // ════════════════════════════════════════════════════════
    // STORIES
    // ════════════════════════════════════════════════════════
    socket.on('story_viewed', async ({ story_id, story_owner_id }) => {
      try {
        const ex = await db.queryOne('SELECT id FROM story_views WHERE story_id=? AND viewer_id=?', [story_id, uid]);
        if (!ex) {
          await db.query('INSERT INTO story_views (story_id, viewer_id) VALUES (?,?)', [story_id, uid]);
          await db.query('UPDATE stories SET views_count=views_count+1 WHERE id=?', [story_id]);
          io.to(`user_${story_owner_id}`).emit('story_view', {
            story_id, viewer: socket.user, viewed_at: new Date().toISOString(),
          });
        }
      } catch {}
    });

    socket.on('story_react', ({ story_id, story_owner_id, emoji }) => {
      io.to(`user_${story_owner_id}`).emit('story_reaction', {
        story_id, reactor: socket.user, emoji,
      });
    });

    // ════════════════════════════════════════════════════════
    // LIVE STREAMS
    // ════════════════════════════════════════════════════════
    socket.on('join_live', async ({ stream_id }) => {
      socket.join(`live_${stream_id}`);
      await db.query('UPDATE live_streams SET viewer_count=viewer_count+1 WHERE id=?', [stream_id]).catch(() => {});
      const count = await db.queryOne('SELECT viewer_count FROM live_streams WHERE id=?', [stream_id]);
      io.to(`live_${stream_id}`).emit('viewer_count_update', { stream_id, count: count?.viewer_count || 0 });
      socket.to(`live_${stream_id}`).emit('viewer_joined', { stream_id, user: socket.user });
    });

    socket.on('leave_live', async ({ stream_id }) => {
      socket.leave(`live_${stream_id}`);
      await db.query('UPDATE live_streams SET viewer_count=GREATEST(0,viewer_count-1) WHERE id=?', [stream_id]).catch(() => {});
      const count = await db.queryOne('SELECT viewer_count FROM live_streams WHERE id=?', [stream_id]);
      io.to(`live_${stream_id}`).emit('viewer_count_update', { stream_id, count: count?.viewer_count || 0 });
    });

    socket.on('live_gift', async ({ stream_id, gift_type, gift_id }) => {
      const gift = gift_id ? await db.queryOne('SELECT * FROM gifts WHERE id=?', [gift_id]) : { name: gift_type, emoji: '🎁' };
      io.to(`live_${stream_id}`).emit('live_gift', {
        stream_id, sender: socket.user, gift, sent_at: new Date().toISOString(),
      });
    });

    socket.on('live_comment', ({ stream_id, content }) => {
      io.to(`live_${stream_id}`).emit('live_comment', {
        stream_id, content, user: socket.user, created_at: new Date().toISOString(),
      });
    });

    // ════════════════════════════════════════════════════════
    // POSTS / REELS
    // ════════════════════════════════════════════════════════
    socket.on('join_post',  ({ post_id })  => socket.join(`post_${post_id}`));
    socket.on('leave_post', ({ post_id })  => socket.leave(`post_${post_id}`));
    socket.on('join_reel',  ({ reel_id })  => socket.join(`reel_${reel_id}`));
    socket.on('leave_reel', ({ reel_id })  => socket.leave(`reel_${reel_id}`));

    // ════════════════════════════════════════════════════════
    // NOTIFICATIONS
    // ════════════════════════════════════════════════════════
    socket.on('notification_read', async ({ notification_id }) => {
      await db.query('UPDATE notifications SET is_read=1 WHERE id=? AND user_id=?', [notification_id, uid]).catch(() => {});
      socket.emit('notification_updated', { notification_id, is_read: true });
    });

    socket.on('notifications_read_all', async () => {
      await db.query('UPDATE notifications SET is_read=1 WHERE user_id=? AND is_read=0', [uid]).catch(() => {});
      socket.emit('all_notifications_read', { user_id: uid });
    });

    // ════════════════════════════════════════════════════════
    // QR LOGIN
    // ════════════════════════════════════════════════════════
    socket.on('join_qr_session', ({ session_id }) => socket.join(`qr_${session_id}`));

    // ════════════════════════════════════════════════════════
    // PRESENCE / STATUS
    // ════════════════════════════════════════════════════════
    socket.on('update_status', async ({ status_text }) => {
      await db.query('UPDATE users SET status_text=? WHERE id=?', [status_text || null, uid]).catch(() => {});
      _broadcastStatus(io, uid, status_text);
    });

    socket.on('set_presence', ({ presence }) => {
      // 'active', 'away', 'busy', 'dnd'
      io.to(`user_${uid}`).emit('presence_updated', { user_id: uid, presence });
    });

    socket.on('request_online_status', ({ user_ids }) => {
      const result = {};
      for (const id of (user_ids || [])) result[id] = isOnline(id);
      socket.emit('online_status_batch', result);
    });

    // ════════════════════════════════════════════════════════
    // DISCONNECT
    // ════════════════════════════════════════════════════════
    socket.on('disconnect', async (reason) => {
      // Clear typing timers for this user
      for (const [k, t] of typingTimers.entries()) {
        if (k.endsWith(`:${uid}`)) { clearTimeout(t); typingTimers.delete(k); }
      }
      removeOnline(uid, socket.id);
      if (!isOnline(uid)) {
        await db.query('UPDATE users SET is_online=0, last_seen=NOW() WHERE id=?', [uid]).catch(() => {});
        _broadcastPresence(io, uid, socket.user, false);
      }
    });

    // ════════════════════════════════════════════════════════
    // PING / HEARTBEAT
    // ════════════════════════════════════════════════════════
    socket.on('ping_server', () => socket.emit('pong_server', { ts: Date.now() }));
  });

  // ── Admin: online count endpoint
  io.of('/').adapter.on?.('join', () => {});
};

async function _broadcastPresence(io, uid, user, online) {
  try {
    const contacts = await db.query(
      `SELECT DISTINCT other_id FROM (
        SELECT contact_id AS other_id FROM contacts WHERE user_id=?
        UNION SELECT user_id AS other_id FROM contacts WHERE contact_id=?
        UNION SELECT follower_id AS other_id FROM follows WHERE following_id=? AND status='accepted'
        UNION SELECT following_id AS other_id FROM follows WHERE follower_id=? AND status='accepted'
      ) t`,
      [uid, uid, uid, uid]
    );
    const payload = { user_id: uid, is_online: online, last_seen: new Date().toISOString(), user };
    for (const c of contacts) io.to(`user_${c.other_id}`).emit('user_online', payload);
  } catch {}
}

async function _broadcastStatus(io, uid, status) {
  try {
    const contacts = await db.query(
      `SELECT DISTINCT other_id FROM (SELECT contact_id AS other_id FROM contacts WHERE user_id=? UNION SELECT user_id AS other_id FROM contacts WHERE contact_id=?) t`,
      [uid, uid]
    );
    for (const c of contacts) io.to(`user_${c.other_id}`).emit('user_status_update', { user_id: uid, status_text: status });
  } catch {}
}
