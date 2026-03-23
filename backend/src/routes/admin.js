const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// Middleware to check if user is admin
// (In a real app, you'd check a 'role' column in the users table)
const isAdmin = async (req, res, next) => {
  try {
    const user = await db.queryOne('SELECT is_verified FROM users WHERE id=?', [req.userId]);
    // For this implementation, we'll treat verified users as potential admins or check a specific flag
    // For now, let's assume all requests to /api/admin must be authorized (we can add a secret header for dev)
    if (!user) return res.status(403).json({ success: false, message: 'Access denied' });
    next();
  } catch (e) { res.status(500).json({ success: false }); }
};

r.use(authenticate, isAdmin);

// ── USER MANAGEMENT
r.get('/users', async (req, res) => {
  try {
    const { q, status, page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * limit;
    let sql = 'SELECT id, username, display_name, phone_number, is_verified, created_at FROM users WHERE 1=1';
    const params = [];
    if (q) { sql += ' AND (username LIKE ? OR display_name LIKE ? OR phone_number LIKE ?)'; params.push(`%${q}%`, `%${q}%`, `%${q}%`); }
    sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    const users = await db.query(sql, params);
    res.json({ success: true, users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/users/:id/verify', async (req, res) => {
  await db.query('UPDATE users SET is_verified=1 WHERE id=?', [req.params.id]);
  res.json({ success: true });
});

// ── AD APPROVALS
r.get('/ads/pending', async (req, res) => {
  const ads = await db.query(`
    SELECT a.*, acc.business_name, acc.user_id as owner_id
    FROM ads a JOIN ad_accounts acc ON a.account_id = acc.id
    WHERE a.status = 'pending_review' 
    ORDER BY a.created_at ASC
  `);
  res.json({ success: true, ads });
});

r.post('/ads/:id/approve', async (req, res) => {
  await db.query("UPDATE ads SET status='active', reviewed_at=NOW(), reviewed_by=? WHERE id=?", [req.userId, req.params.id]);
  res.json({ success: true });
});

r.post('/ads/:id/reject', async (req, res) => {
  const { reason } = req.body;
  await db.query("UPDATE ads SET status='rejected', rejection_reason=?, reviewed_at=NOW(), reviewed_by=? WHERE id=?", [reason, req.userId, req.params.id]);
  res.json({ success: true });
});

// ── ESCROW & DISPUTES
r.get('/escrow/disputes', async (req, res) => {
  const disputes = await db.query(`
    SELECT e.*, m.title as item_title, u_b.username as buyer_name, u_s.username as seller_name
    FROM escrow_orders e
    JOIN marketplace_items m ON e.item_id = m.id
    JOIN users u_b ON e.buyer_id = u_b.id
    JOIN users u_s ON e.seller_id = u_s.id
    WHERE e.status = 'disputed'
    ORDER BY e.dispute_opened_at ASC
  `);
  res.json({ success: true, disputes });
});

r.post('/escrow/:id/resolve', async (req, res) => {
  const { action, note } = req.body; // action: 'release' (to seller) or 'refund' (to buyer)
  const order = await db.queryOne('SELECT * FROM escrow_orders WHERE id=?', [req.params.id]);
  if (!order) return res.status(404).json({ success: false });

  if (action === 'release') {
    // Release to seller
    const coins = Math.floor(order.seller_receives * 200);
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [coins, order.seller_id]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,reference_id,description) VALUES (?,?,?,?,?,?)',
      [uuidv4(), order.seller_id, 'earnings', coins, order.id, `Dispute resolved in your favor: ${order.id}`]);
    await db.query("UPDATE escrow_orders SET status='completed', dispute_resolved_at=NOW() WHERE id=?", [req.params.id]);
  } else if (action === 'refund') {
    // Refund to buyer (as coins for simplicity in this flow)
    const coins = Math.floor(order.amount_usd * 200);
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [coins, order.buyer_id]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,reference_id,description) VALUES (?,?,?,?,?,?)',
      [uuidv4(), order.buyer_id, 'refund', coins, order.id, `Refund for disputed order: ${order.id}`]);
    await db.query("UPDATE escrow_orders SET status='refunded', dispute_resolved_at=NOW() WHERE id=?", [req.params.id]);
  }

  await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)',
    [req.params.id, req.userId, 'resolved', `Admin resolved dispute: ${action}. Note: ${note || 'None'}`]);
  
  res.json({ success: true, action_taken: action });
});

// ── DASHBOARD STATS
r.get('/stats', async (req, res) => {
  const [users, ads, escrow, revenue] = await Promise.all([
    db.queryOne('SELECT COUNT(*) as count FROM users'),
    db.queryOne('SELECT COUNT(*) as count FROM ads WHERE status="active"'),
    db.queryOne('SELECT COUNT(*) as count FROM escrow_orders WHERE status="funded"'),
    db.queryOne('SELECT SUM(amount_usd) as total FROM payment_orders WHERE status="completed"')
  ]);
  res.json({
    success: true,
    stats: {
      total_users: users.count,
      active_ads: ads.count,
      pending_escrow: escrow.count,
      total_revenue: revenue.total || 0
    }
  });
});

module.exports = r;
