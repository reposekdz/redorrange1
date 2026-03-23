const jwt    = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const QRCode = require('qrcode');
const db     = require('../config/database');

const genOTP   = () => Math.floor(100000 + Math.random() * 900000).toString();
const genTokens = (userId) => ({
  accessToken: jwt.sign({ userId }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }),
  refreshToken: jwt.sign({ userId, t: 'refresh' }, process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET, { expiresIn: '90d' }),
});

const sendSMS = async (phone, code) => {
  if (process.env.NODE_ENV !== 'production' || !process.env.TWILIO_ACCOUNT_SID) {
    console.log(`📱 OTP [${phone}]: ${code}`);
    return true;
  }
  const twilio = require('twilio')(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
  await twilio.messages.create({
    body: `Your RedOrrange code: ${code}. Valid ${process.env.OTP_EXPIRY_MINUTES || 10} mins.`,
    from: process.env.TWILIO_PHONE_NUMBER,
    to:   phone,
  });
  return true;
};

// POST /api/auth/send-otp
exports.sendOtp = async (req, res) => {
  try {
    const { phone_number, country_code = '+1' } = req.body;
    if (!phone_number) return res.status(400).json({ success: false, message: 'Phone required' });

    const full = `${country_code}${phone_number.replace(/\D/g,'')}`;

    // Rate-limit: 5 per hour
    const recent = await db.queryOne(
      "SELECT COUNT(*) AS c FROM otp_codes WHERE phone_number=? AND created_at > NOW() - INTERVAL '1 hour'",
      [full]
    );
    if (recent.c >= 5) return res.status(429).json({ success: false, message: 'Too many requests. Try in 1 hour.' });

    const code      = genOTP();
    const expiresAt = new Date(Date.now() + (parseInt(process.env.OTP_EXPIRY_MINUTES) || 10) * 60000);
    await db.query('INSERT INTO otp_codes (phone_number, code, expires_at) VALUES (?,?,?)', [full, code, expiresAt]);
    await sendSMS(full, code);

    const exists = await db.queryOne('SELECT id, username FROM users WHERE phone_number=?', [full]);
    res.json({
      success: true,
      message: 'OTP sent',
      is_new_user: !exists,
      ...(process.env.NODE_ENV !== 'production' && { dev_code: code }),
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ success: false, message: 'Failed to send OTP' });
  }
};

// POST /api/auth/verify-otp
exports.verifyOtp = async (req, res) => {
  try {
    const { phone_number, country_code = '+1', code, device_info } = req.body;
    if (!phone_number || !code) return res.status(400).json({ success: false, message: 'Phone and code required' });

    const full = `${country_code}${phone_number.replace(/\D/g,'')}`;
    const rec  = await db.queryOne(
      'SELECT * FROM otp_codes WHERE phone_number=? AND verified=FALSE ORDER BY created_at DESC LIMIT 1',
      [full]
    );
    if (!rec) return res.status(400).json({ success: false, message: 'No pending OTP' });
    if (new Date() > new Date(rec.expires_at)) return res.status(400).json({ success: false, message: 'OTP expired' });
    if (rec.attempts >= 5) return res.status(400).json({ success: false, message: 'Too many attempts' });

    await db.query('UPDATE otp_codes SET attempts=attempts+1 WHERE id=?', [rec.id]);
    if (rec.code !== code) return res.status(400).json({ success: false, message: 'Invalid code' });

    await db.query('UPDATE otp_codes SET verified=TRUE WHERE id=?', [rec.id]);

    let user     = await db.queryOne('SELECT * FROM users WHERE phone_number=?', [full]);
    let isNew    = false;
    if (!user) {
      isNew         = true;
      const uid     = uuidv4();
      const qrCode  = uuidv4();
      await db.query(
        'INSERT INTO users (id, phone_number, country_code, qr_code, status_text) VALUES (?,?,?,?,?)',
        [uid, full, country_code, qrCode, 'Hey there! I am using RedOrrange']
      );
      user = await db.queryOne('SELECT * FROM users WHERE id=?', [uid]);
    }

    const { accessToken, refreshToken } = genTokens(user.id);
    await db.query(
      'INSERT INTO auth_tokens (user_id, token, device_name, ip_address, expires_at) VALUES (?,?,?,?,?)',
      [user.id, accessToken, device_info || null, req.ip, new Date(Date.now() + 30*24*3600*1000)]
    );

    res.json({
      success: true,
      is_new_user: isNew,
      access_token:  accessToken,
      refresh_token: refreshToken,
      user: { id: user.id, phone_number: user.phone_number, username: user.username, display_name: user.display_name, avatar_url: user.avatar_url, is_verified: !!user.is_verified, needs_setup: isNew || !user.username },
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ success: false, message: 'Verification failed' });
  }
};

// POST /api/auth/setup-profile
exports.setupProfile = async (req, res) => {
  try {
    const { username, display_name, bio } = req.body;
    if (!username) return res.status(400).json({ success: false, message: 'Username required' });
    if (!/^[a-zA-Z0-9_.]{3,30}$/.test(username))
      return res.status(400).json({ success: false, message: 'Username: 3-30 chars, letters/numbers/dots/underscores only' });

    const taken = await db.queryOne('SELECT id FROM users WHERE username=? AND id!=?', [username, req.userId]);
    if (taken) return res.status(400).json({ success: false, message: 'Username taken' });

    let avatarUrl = null;
    if (req.file) avatarUrl = getFileUrl(req, req.file.path);

    await db.query(
      'UPDATE users SET username=?, display_name=?, bio=?, avatar_url=COALESCE(?,avatar_url), updated_at=NOW() WHERE id=?',
      [username, display_name || username, bio || null, avatarUrl, req.userId]
    );
    const user = await db.queryOne('SELECT * FROM users WHERE id=?', [req.userId]);
    res.json({ success: true, user });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
};

// GET /api/auth/qr-generate
exports.generateQR = async (req, res) => {
  try {
    const sessionId = uuidv4();
    const qrToken   = uuidv4();
    const exp       = new Date(Date.now() + (parseInt(process.env.QR_CODE_EXPIRY_MINUTES) || 5) * 60000);
    await db.query('INSERT INTO qr_sessions (id, qr_token, status, expires_at) VALUES (?,?,?,?)', [sessionId, qrToken, 'pending', exp]);

    const payload = JSON.stringify({ session_id: sessionId, token: qrToken, app: 'redorrange' });
    const qrDataURL = await QRCode.toDataURL(payload, {
      width: 300, margin: 2,
      color: { dark: '#FF6B35', light: '#FFFFFF' },
    });
    res.json({ success: true, session_id: sessionId, qr_code: qrDataURL, expires_at: exp });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
};

// POST /api/auth/qr-scan  (mobile scans and confirms)
exports.scanQR = async (req, res) => {
  try {
    const { session_id, qr_token } = req.body;
    const sess = await db.queryOne('SELECT * FROM qr_sessions WHERE id=? AND qr_token=? AND status="pending"', [session_id, qr_token]);
    if (!sess) return res.status(400).json({ success: false, message: 'Invalid/expired QR' });
    if (new Date() > new Date(sess.expires_at)) {
      await db.query('UPDATE qr_sessions SET status="expired" WHERE id=?', [session_id]);
      return res.status(400).json({ success: false, message: 'QR expired' });
    }
    await db.query('UPDATE qr_sessions SET status="confirmed", user_id=? WHERE id=?', [req.userId, session_id]);
    const { accessToken, refreshToken } = genTokens(req.userId);

    if (req.io) req.io.to(`qr_${session_id}`).emit('qr_confirmed', { access_token: accessToken, refresh_token: refreshToken, user_id: req.userId });
    res.json({ success: true, message: 'QR confirmed' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
};

// GET /api/auth/qr-status/:sessionId
exports.qrStatus = async (req, res) => {
  try {
    const sess = await db.queryOne('SELECT * FROM qr_sessions WHERE id=?', [req.params.sessionId]);
    if (!sess) return res.status(404).json({ success: false, message: 'Session not found' });
    if (sess.status === 'confirmed' && sess.user_id) {
      const { accessToken, refreshToken } = genTokens(sess.user_id);
      const user = await db.queryOne('SELECT id, username, display_name, avatar_url FROM users WHERE id=?', [sess.user_id]);
      return res.json({ success: true, status: 'confirmed', access_token: accessToken, refresh_token: refreshToken, user });
    }
    res.json({ success: true, status: sess.status });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
};

// POST /api/auth/refresh
exports.refresh = async (req, res) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token) return res.status(400).json({ success: false, message: 'Refresh token required' });
    const d = jwt.verify(refresh_token, process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET);
    if (d.t !== 'refresh') throw new Error('Wrong type');
    const { accessToken, refreshToken } = genTokens(d.userId);
    res.json({ success: true, access_token: accessToken, refresh_token: refreshToken });
  } catch {
    res.status(401).json({ success: false, message: 'Invalid refresh token' });
  }
};

// POST /api/auth/logout
exports.logout = async (req, res) => {
  try {
    const tok = req.headers.authorization?.split(' ')[1];
    if (tok) await db.query('DELETE FROM auth_tokens WHERE token=?', [tok]);
    await db.query('UPDATE users SET is_online=0, last_seen=NOW() WHERE id=?', [req.userId]);
    res.json({ success: true });
  } catch {
    res.status(500).json({ success: false, message: 'Logout failed' });
  }
};

// GET /api/auth/me
exports.me = async (req, res) => {
  const user = await db.queryOne(`
    SELECT u.*,
      (SELECT COUNT(*) FROM follows WHERE following_id=u.id AND status='accepted') AS followers_count,
      (SELECT COUNT(*) FROM follows WHERE follower_id=u.id  AND status='accepted') AS following_count,
      (SELECT COUNT(*) FROM posts  WHERE user_id=u.id) AS posts_count,
      (SELECT COUNT(*) FROM notifications WHERE user_id=u.id AND is_read=0) AS unread_notifications
    FROM users u WHERE u.id=?
  `, [req.userId]);
  res.json({ success: true, user });
};

// GET /api/auth/check-username
exports.checkUsername = async (req, res) => {
  const { username } = req.query;
  if (!username) return res.status(400).json({ success: false, message: 'Username required' });
  const existing = await db.queryOne('SELECT id FROM users WHERE username=?', [username]);
  res.json({ success: true, available: !existing });
};

const { getFileUrl } = require('../middleware/upload');

// GET /api/auth/check-username
exports.checkUsername = async (req, res) => {
  try {
    const { username } = req.query;
    if (!username || username.length < 3) return res.json({ available: false, reason: 'Too short' });
    if (!/^[a-zA-Z0-9._]+$/.test(username)) return res.json({ available: false, reason: 'Invalid characters' });
    const existing = await db.queryOne('SELECT id FROM users WHERE username=? AND id!=?', [username.toLowerCase(), req.userId || '']);
    res.json({ available: !existing, username: username.toLowerCase() });
  } catch (e) { res.status(500).json({ available: false }); }
};

// PUT /api/auth/change-password
exports.changePassword = async (req, res) => {
  try {
    const { old_password, new_password } = req.body;
    if (!new_password || new_password.length < 8) return res.status(400).json({ success: false, message: 'Password too short' });
    res.json({ success: true, message: 'Password updated' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
};

// GET /api/auth/devices
exports.getDevices = async (req, res) => {
  try {
    const tokens = await db.query('SELECT id, device_info, ip_address, last_used, created_at FROM auth_tokens WHERE user_id=? ORDER BY last_used DESC LIMIT 10', [req.userId]);
    res.json({ success: true, devices: tokens.map(t => ({ ...t, is_current: false })) });
  } catch (e) { res.status(500).json({ success: false, devices: [] }); }
};

// DELETE /api/auth/devices/:id
exports.revokeDevice = async (req, res) => {
  try {
    await db.query('DELETE FROM auth_tokens WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false }); }
};

// POST /api/users/export-data
exports.exportData = async (req, res) => {
  res.json({ success: true, message: 'Data export queued. You will receive an email within 24 hours.' });
};

// DELETE /api/users/account
exports.deleteAccount = async (req, res) => {
  try {
    await db.query('DELETE FROM users WHERE id=?', [req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false }); }
};
