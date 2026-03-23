// routes/marketplace.js
const express = require('express');
const r = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const db = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const P = require('../services/paymentService');

r.get('/', authenticate, async (req, res) => {
  try {
    const { category, q, min_price, max_price, condition_type, page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * limit;
    let sql = `SELECT m.*, u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT COUNT(*) > 0 FROM marketplace_saves WHERE item_id=m.id AND user_id=?) AS is_saved
      FROM marketplace_items m JOIN users u ON m.seller_id=u.id WHERE m.status='active'`;
    const params = [req.userId];
    if (category) { sql += ' AND m.category=?'; params.push(category); }
    if (q) { sql += ' AND (m.title LIKE ? OR m.description LIKE ?)'; params.push(`%${q}%`, `%${q}%`); }
    if (min_price) { sql += ' AND m.price>=?'; params.push(min_price); }
    if (max_price) { sql += ' AND m.price<=?'; params.push(max_price); }
    if (condition_type) { sql += ' AND m.condition_type=?'; params.push(condition_type); }
    sql += ' ORDER BY m.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    const items = await db.query(sql, params);
    items.forEach(i => i.is_saved = !!i.is_saved);
    res.json({ success: true, items, has_more: items.length === parseInt(limit) });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/', authenticate, upload.array('images', 10), async (req, res) => {
  try {
    const { title, description, price, currency = 'USD', category, condition_type = 'used', location } = req.body;
    if (!title) return res.status(400).json({ success: false, message: 'Title required' });
    const images = (req.files || []).map(f => getFileUrl(req, f.path));
    const id = uuidv4();
    await db.query('INSERT INTO marketplace_items (id, seller_id, title, description, price, currency, category, condition_type, location, images) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [id, req.userId, title, description || null, price || null, currency, category || null, condition_type, location || null, JSON.stringify(images)]);
    const item = await db.queryOne('SELECT m.*, u.username, u.display_name, u.avatar_url FROM marketplace_items m JOIN users u ON m.seller_id=u.id WHERE m.id=?', [id]);
    res.status(201).json({ success: true, item });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/:id', authenticate, async (req, res) => {
  const item = await db.queryOne(`SELECT m.*, u.username, u.display_name, u.avatar_url, u.is_verified,
    (SELECT COUNT(*) > 0 FROM marketplace_saves WHERE item_id=m.id AND user_id=?) AS is_saved
    FROM marketplace_items m JOIN users u ON m.seller_id=u.id WHERE m.id=?`, [req.userId, req.params.id]);
  if (!item) return res.status(404).json({ success: false, message: 'Not found' });
  item.is_saved = !!item.is_saved;
  await db.query('UPDATE marketplace_items SET views_count=views_count+1 WHERE id=?', [req.params.id]);
  res.json({ success: true, item });
});

r.put('/:id', authenticate, async (req, res) => {
  const { title, description, price, status } = req.body;
  const item = await db.queryOne('SELECT id FROM marketplace_items WHERE id=? AND seller_id=?', [req.params.id, req.userId]);
  if (!item) return res.status(404).json({ success: false, message: 'Not found' });
  const fields = {}; if (title) fields.title = title; if (description !== undefined) fields.description = description; if (price !== undefined) fields.price = price; if (status) fields.status = status;
  const sets = Object.keys(fields).map(k => `${k}=?`).join(', ');
  if (sets) await db.query(`UPDATE marketplace_items SET ${sets}, updated_at=NOW() WHERE id=?`, [...Object.values(fields), req.params.id]);
  const updated = await db.queryOne('SELECT * FROM marketplace_items WHERE id=?', [req.params.id]);
  res.json({ success: true, item: updated });
});

r.post('/:id/save', authenticate, async (req, res) => {
  const ex = await db.queryOne('SELECT id FROM marketplace_saves WHERE item_id=? AND user_id=?', [req.params.id, req.userId]);
  if (ex) { await db.query('DELETE FROM marketplace_saves WHERE item_id=? AND user_id=?', [req.params.id, req.userId]); return res.json({ success: true, saved: false }); }
  await db.query('INSERT INTO marketplace_saves (item_id, user_id) VALUES (?,?)', [req.params.id, req.userId]);
  res.json({ success: true, saved: true });
});

r.delete('/:id', authenticate, async (req, res) => {
  await db.query('UPDATE marketplace_items SET status="deleted" WHERE id=? AND seller_id=?', [req.params.id, req.userId]);
  res.json({ success: true });
});

r.get('/user/my-listings', authenticate, async (req, res) => {
  const items = await db.query('SELECT * FROM marketplace_items WHERE seller_id=? AND status!="deleted" ORDER BY created_at DESC', [req.userId]);
  res.json({ success: true, items });
});

r.get('/user/orders', authenticate, async (req, res) => {
  const orders = await db.query(`SELECT e.*, m.title, m.images, m.currency, u.username as seller_name 
    FROM escrow_orders e JOIN marketplace_items m ON e.item_id=m.id JOIN users u ON e.seller_id=u.id 
    WHERE e.buyer_id=? ORDER BY e.created_at DESC`, [req.userId]);
  res.json({ success: true, orders });
});

r.get('/user/sales', authenticate, async (req, res) => {
  const orders = await db.query(`SELECT e.*, m.title, m.images, m.currency, u.username as buyer_name 
    FROM escrow_orders e JOIN marketplace_items m ON e.item_id=m.id JOIN users u ON e.buyer_id=u.id 
    WHERE e.seller_id=? ORDER BY e.created_at DESC`, [req.userId]);
  res.json({ success: true, orders });
});

// ── BUY ITEM (Escrow Checkout)
r.post('/:id/buy', authenticate, async (req, res) => {
  try {
    const { payment_method = 'stripe', currency = 'USD' } = req.body;
    const item = await db.queryOne('SELECT * FROM marketplace_items WHERE id=? AND status="active"', [req.params.id]);
    if (!item) return res.status(404).json({ success: false, message: 'Item not available' });
    if (item.seller_id === req.userId) return res.status(400).json({ success: false, message: 'Cannot buy your own item' });

    const amountUsd = parseFloat(item.price);
    const platformFee = amountUsd * 0.05;
    const sellerReceives = amountUsd - platformFee;

    const escrowId = uuidv4();
    await db.query('INSERT INTO escrow_orders (id, buyer_id, seller_id, item_id, amount_usd, platform_fee, seller_receives, status) VALUES (?,?,?,?,?,?,?,?)',
      [escrowId, req.userId, item.seller_id, item.id, amountUsd, platformFee, sellerReceives, 'pending']);
    
    await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)',
      [escrowId, req.userId, 'created', `Order initiated for ${item.title}`]);

    const orderId = uuidv4();
    await db.query('INSERT INTO payment_orders (id, user_id, amount_usd, currency, payment_method, status, target_type, target_id) VALUES (?,?,?,?,?,?,?,?)',
      [orderId, req.userId, amountUsd, currency, payment_method, 'pending', 'marketplace_item', escrowId]);

    let paymentData = {};
    if (payment_method === 'stripe') {
      paymentData = await P.stripeCreateIntent({ amountUsd, currency, orderId, description: `Marketplace: ${item.title}`, userId: req.userId });
      await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [paymentData.payment_intent_id, orderId]);
    } else if (payment_method === 'paypal') {
      paymentData = await P.paypalCreateOrder({ amountUsd, currency, orderId, description: `Marketplace: ${item.title}` });
      await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [paymentData.paypal_order_id, orderId]);
    } else if (payment_method === 'flutterwave') {
      const user = await db.queryOne('SELECT email, display_name, phone_number FROM users WHERE id=?', [req.userId]);
      paymentData = await P.fwPaymentLink({ amount: P.toLocal(amountUsd, currency), currency, orderId, email: user?.email, name: user?.display_name, phone: user?.phone_number, narration: `Marketplace: ${item.title}` });
      await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [paymentData.tx_ref, orderId]);
    }

    res.json({ success: true, order_id: orderId, escrow_id: escrowId, ...paymentData });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── ESCROW MANAGEMENT
r.get('/escrow/:id', authenticate, async (req, res) => {
  const order = await db.queryOne(`SELECT e.*, m.title, m.images, u_s.username as seller_name, u_b.username as buyer_name
    FROM escrow_orders e 
    JOIN marketplace_items m ON e.item_id=m.id
    JOIN users u_s ON e.seller_id=u_s.id
    JOIN users u_b ON e.buyer_id=u_b.id
    WHERE e.id=? AND (e.buyer_id=? OR e.seller_id=?)`, [req.params.id, req.userId, req.userId]);
  if (!order) return res.status(404).json({ success: false, message: 'Order not found' });
  res.json({ success: true, order });
});

r.post('/escrow/:id/ship', authenticate, async (req, res) => {
  const { tracking_number } = req.body;
  const order = await db.queryOne('SELECT id FROM escrow_orders WHERE id=? AND seller_id=? AND status="funded"', [req.params.id, req.userId]);
  if (!order) return res.status(404).json({ success: false, message: 'Order not found or not ready' });
  await db.query('UPDATE escrow_orders SET status="in_transit", tracking_number=?, updated_at=NOW() WHERE id=?', [tracking_number||null, req.params.id]);
  await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)', [req.params.id, req.userId, 'shipped', `Item marked as shipped${tracking_number?': '+tracking_number:''}`]);
  res.json({ success: true, status: 'in_transit' });
});

r.post('/escrow/:id/deliver', authenticate, async (req, res) => {
  const order = await db.queryOne('SELECT id FROM escrow_orders WHERE id=? AND seller_id=? AND status="in_transit"', [req.params.id, req.userId]);
  if (!order) return res.status(404).json({ success: false, message: 'Order not found or not in transit' });
  await db.query('UPDATE escrow_orders SET status="delivered", updated_at=NOW() WHERE id=?', [req.params.id]);
  await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)', [req.params.id, req.userId, 'delivered', 'Item marked as delivered']);
  res.json({ success: true, status: 'delivered' });
});

r.post('/escrow/:id/confirm', authenticate, async (req, res) => {
  try {
    const order = await db.queryOne('SELECT * FROM escrow_orders WHERE id=? AND buyer_id=? AND status IN ("delivered","in_transit","funded")', [req.params.id, req.userId]);
    if (!order) return res.status(404).json({ success: false, message: 'Order not found or not ready' });
    
    // Release funds to seller wallet
    const sellerWallet = await db.queryOne('SELECT id FROM user_wallets WHERE user_id=?', [order.seller_id]);
    if (!sellerWallet) await db.query('INSERT INTO user_wallets (id, user_id, coins) VALUES (?,?,0)', [uuidv4(), order.seller_id]);
    
    // Convert USD to coins for simplicity in the current wallet system, or we could handle USD balance.
    // The user's wallet system seems to be coin-based (coins).
    const coins = Math.floor(order.seller_receives * 200); // 1 USD = 200 coins as per .env.example
    
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [coins, order.seller_id]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,reference_id,description) VALUES (?,?,?,?,?,?)',
      [uuidv4(), order.seller_id, 'earnings', coins, order.id, `Marketplace sale: order ${order.id}`]);

    await db.query('UPDATE escrow_orders SET status="completed", completed_at=NOW(), buyer_confirmed=1 WHERE id=?', [req.params.id]);
    await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)', [req.params.id, req.userId, 'confirmed', 'Buyer confirmed receipt, funds released to seller']);
    
    res.json({ success: true, status: 'completed', coins_released: coins });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/escrow/:id/dispute', authenticate, async (req, res) => {
  const { reason } = req.body;
  if (!reason) return res.status(400).json({ success: false, message: 'Reason required' });
  const order = await db.queryOne('SELECT id FROM escrow_orders WHERE id=? AND buyer_id=? AND status IN ("funded","in_transit","delivered")', [req.params.id, req.userId]);
  if (!order) return res.status(404).json({ success: false, message: 'Order not found' });
  await db.query('UPDATE escrow_orders SET status="disputed", dispute_reason=?, dispute_opened_at=NOW() WHERE id=?', [reason, req.params.id]);
  await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)', [req.params.id, req.userId, 'disputed', `Buyer opened a dispute: ${reason}`]);
  res.json({ success: true, status: 'disputed' });
});

module.exports = r;
