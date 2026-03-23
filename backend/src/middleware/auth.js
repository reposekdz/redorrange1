// src/middleware/auth.js
const jwt = require('jsonwebtoken');
const db  = require('../config/database');

const authenticate = async (req, res, next) => {
  try {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer '))
      return res.status(401).json({ success: false, message: 'No token' });

    const token   = header.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    const user = await db.queryOne(
      'SELECT id, phone_number, username, display_name, avatar_url, is_verified, is_private FROM users WHERE id=?',
      [decoded.userId]
    );
    if (!user) return res.status(401).json({ success: false, message: 'User not found' });

    req.user   = user;
    req.userId = user.id;

    // async last seen
    db.query('UPDATE users SET is_online=1, last_seen=NOW() WHERE id=?', [user.id]).catch(() => {});
    next();
  } catch (e) {
    if (e.name === 'TokenExpiredError') return res.status(401).json({ success: false, message: 'Token expired' });
    if (e.name === 'JsonWebTokenError')  return res.status(401).json({ success: false, message: 'Invalid token' });
    next(e);
  }
};

const optionalAuth = async (req, res, next) => {
  try {
    const header = req.headers.authorization;
    if (header?.startsWith('Bearer ')) {
      const token   = header.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      const user    = await db.queryOne('SELECT id, username, display_name, avatar_url FROM users WHERE id=?', [decoded.userId]);
      req.user   = user;
      req.userId = user?.id;
    }
  } catch {}
  next();
};

module.exports = { authenticate, optionalAuth };
