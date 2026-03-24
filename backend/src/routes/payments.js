'use strict';
const express = require('express');
const r       = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const db      = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const P       = require('../services/paymentService');

// Helper: get or create order
async function newOrder(userId, packageId, amountUsd, amountLocal, currency, coins, bonusCoins, method, targetType='coin_package', targetId=null) {
  const id = uuidv4();
  await db.query(
    'INSERT INTO payment_orders (id,user_id,package_id,amount_usd,amount_local,currency,coins,bonus_coins,payment_method,status,target_type,target_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
    [id, userId, packageId||null, amountUsd, amountLocal||null, currency||'USD', coins||0, bonusCoins||0, method, 'pending', targetType, targetId]
  );
  return id;
}

// ══════════════════════════════════════════════════════
// PACKAGES & WALLET
// ══════════════════════════════════════════════════════
r.get('/packages', authenticate, async (req, res) => {
  try {
    const currency = (req.query.currency || 'USD').toUpperCase();
    const pkgs = await db.query("SELECT * FROM coin_packages WHERE is_active=1 ORDER BY price_usd");
    pkgs.forEach(p => { p.price_local = P.toLocal(p.price_usd, currency); p.currency = currency; p.symbol = P.sym(currency); });
    res.json({ success: true, packages: pkgs, currency, exchange_rates: P.RATES });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/wallet', authenticate, async (req, res) => {
  try {
    let w = await db.queryOne('SELECT * FROM user_wallets WHERE user_id=?', [req.userId]);
    if (!w) { await db.query('INSERT INTO user_wallets (id,user_id,coins) VALUES (?,?,0)', [uuidv4(), req.userId]); w = { coins:0 }; }
    const [txns, sub, orders] = await Promise.all([
      db.query('SELECT * FROM coin_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT 30', [req.userId]),
      db.queryOne("SELECT us.*,sp.name plan_name,sp.features FROM user_subscriptions us JOIN subscription_plans sp ON us.plan_id=sp.id WHERE us.user_id=? AND us.status='active' AND us.expires_at>NOW()", [req.userId]),
      db.query("SELECT * FROM payment_orders WHERE user_id=? ORDER BY created_at DESC LIMIT 10", [req.userId]),
    ]);
    res.json({ success: true, wallet: w, transactions: txns, subscription: sub||null, recent_orders: orders });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/order/:id', authenticate, async (req, res) => {
  try {
    const o = await db.queryOne('SELECT po.*,cp.name package_name,cp.coins pkg_coins FROM payment_orders po LEFT JOIN coin_packages cp ON po.package_id=cp.id WHERE po.id=? AND po.user_id=?', [req.params.id, req.userId]);
    if (!o) return res.status(404).json({ success: false, message: 'Order not found' });
    res.json({ success: true, order: o });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/history', authenticate, async (req, res) => {
  try {
    const { limit=30, offset=0 } = req.query;
    const [orders, txns] = await Promise.all([
      db.query('SELECT po.*,cp.name package_name FROM payment_orders po LEFT JOIN coin_packages cp ON po.package_id=cp.id WHERE po.user_id=? ORDER BY po.created_at DESC LIMIT ? OFFSET ?', [req.userId, parseInt(limit), parseInt(offset)]),
      db.query('SELECT * FROM coin_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT ? OFFSET ?', [req.userId, parseInt(limit), parseInt(offset)]),
    ]);
    res.json({ success: true, orders, transactions: txns });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ══════════════════════════════════════════════════════
// STRIPE
// ══════════════════════════════════════════════════════

// Create payment intent
r.post('/stripe/intent', authenticate, async (req, res) => {
  try {
    const { package_id, amount_usd, description, currency='USD' } = req.body;
    let usd=parseFloat(amount_usd||0), coins=0, bonus=0, pkgId=package_id;
    if (package_id) {
      const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
      if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
      usd=parseFloat(pkg.price_usd); coins=pkg.coins; bonus=pkg.bonus_coins||0;
    }
    if (usd <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });
    const orderId = await newOrder(req.userId, pkgId, usd, P.toLocal(usd,currency), currency, coins, bonus, 'stripe', 'coin_package', pkgId);
    const intent  = await P.stripeCreateIntent({ amountUsd: usd, currency, orderId, description: description||`RedOrrange ${coins} coins`, userId: req.userId });
    await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [intent.payment_intent_id, orderId]);
    res.json({ success: true, order_id: orderId, ...intent });
  } catch (e) { console.error('[Stripe Intent]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// Confirm after client-side payment
r.post('/stripe/confirm', authenticate, async (req, res) => {
  try {
    const { payment_intent_id, order_id } = req.body;
    if (!payment_intent_id) return res.status(400).json({ success: false, message: 'payment_intent_id required' });
    const result = await P.stripeConfirmIntent(payment_intent_id);
    if (!result.success) return res.json({ success: false, status: result.status, message: `Payment ${result.status}` });
    const fulfil = await P.fulfillOrder(order_id, payment_intent_id, req.io);
    res.json({ success: fulfil.success, status: 'completed', ...fulfil });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// Stripe Subscription
r.post('/stripe/subscription', authenticate, async (req, res) => {
  try {
    const { plan_id, stripe_price_id } = req.body;
    if (!stripe_price_id) return res.status(400).json({ success: false, message: 'stripe_price_id required' });
    const plan = await db.queryOne('SELECT * FROM subscription_plans WHERE id=? AND is_active=1', [plan_id]);
    if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
    const result = await P.stripeCreateSubscription({ userId: req.userId, stripePriceId: stripe_price_id });
    res.json({ success: true, plan, ...result });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// Stripe Webhook (raw body — registered before express.json in server.js)
r.post('/stripe/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;
  try { event = P.stripeVerifyWebhook(req.body, sig); }
  catch (e) { console.error('[Stripe Webhook] sig fail:', e.message); return res.status(400).send(`Webhook Error: ${e.message}`); }
  try {
    switch (event.type) {
      case 'payment_intent.succeeded': {
        const pi  = event.data.object;
        const oid = pi.metadata?.order_id;
        if (oid) await P.fulfillOrder(oid, pi.id, req.io);
        break;
      }
      case 'payment_intent.payment_failed': {
        const pi  = event.data.object;
        const oid = pi.metadata?.order_id;
        if (oid) await db.query("UPDATE payment_orders SET status='failed',failure_reason=? WHERE id=?", [pi.last_payment_error?.message||'Payment failed', oid]);
        break;
      }
      case 'invoice.payment_succeeded': {
        const inv = event.data.object;
        const cid = inv.customer;
        if (cid) {
          const u = await db.queryOne('SELECT id FROM users WHERE stripe_customer_id=?', [cid]);
          if (u) {
            const priceId = inv.lines?.data?.[0]?.price?.id;
            const plan    = await db.queryOne('SELECT * FROM subscription_plans WHERE stripe_price_id=?', [priceId]).catch(()=>null);
            if (plan) {
              const exp = new Date(Date.now() + (plan.duration_days||30)*86400000);
              await db.query(
                "INSERT INTO user_subscriptions (id,user_id,plan_id,status,expires_at,auto_renew) VALUES (?,?,?,'active',?,1) ON CONFLICT (user_id,plan_id) DO UPDATE SET status='active', expires_at=EXCLUDED.expires_at",
                [uuidv4(), u.id, plan.id, exp]);
              if (req.io) req.io.to(`user_${u.id}`).emit('subscription_activated', { plan_name: plan.name, expires_at: exp });
            }
          }
        }
        break;
      }
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        if (sub.customer) {
          const u = await db.queryOne('SELECT id FROM users WHERE stripe_customer_id=?', [sub.customer]);
          if (u) await db.query("UPDATE user_subscriptions SET status='cancelled' WHERE user_id=?", [u.id]);
        }
        break;
      }
    }
    res.json({ received: true });
  } catch (e) { console.error('[Stripe Webhook] handler:', e.message); res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════
// PAYPAL
// ══════════════════════════════════════════════════════

r.post('/paypal/create', authenticate, async (req, res) => {
  try {
    const { package_id, amount_usd, currency='USD', description } = req.body;
    let usd=parseFloat(amount_usd||0), coins=0, bonus=0;
    if (package_id) {
      const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
      if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
      usd=parseFloat(pkg.price_usd); coins=pkg.coins; bonus=pkg.bonus_coins||0;
    }
    if (usd <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });
    const orderId = await newOrder(req.userId, package_id, usd, P.toLocal(usd,currency), currency, coins, bonus, 'paypal', 'coin_package', package_id);
    const result  = await P.paypalCreateOrder({ amountUsd: usd, currency, orderId, description: description||`RedOrrange ${coins} coins` });
    await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [result.paypal_order_id, orderId]);
    res.json({ success: true, order_id: orderId, paypal_order_id: result.paypal_order_id, approve_url: result.approve_url, status: result.status });
  } catch (e) { console.error('[PayPal Create]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

r.post('/paypal/capture', authenticate, async (req, res) => {
  try {
    const { paypal_order_id, order_id } = req.body;
    if (!paypal_order_id) return res.status(400).json({ success: false, message: 'paypal_order_id required' });
    const cap = await P.paypalCaptureOrder(paypal_order_id);
    if (!cap.success) {
      await db.query("UPDATE payment_orders SET status='failed',failure_reason=? WHERE id=?", [`PayPal: ${cap.status}`, order_id]);
      return res.json({ success: false, status: cap.status });
    }
    const fulfil = await P.fulfillOrder(order_id, cap.capture_id, req.io);
    res.json({ success: fulfil.success, capture_id: cap.capture_id, ...fulfil });
  } catch (e) { console.error('[PayPal Capture]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

r.post('/paypal/webhook', express.json(), async (req, res) => {
  try {
    const valid = await P.paypalVerifyWebhook(req.headers, req.body);
    if (!valid && process.env.NODE_ENV === 'production') return res.status(401).json({ success: false });
    const event = req.body;
    if (event.event_type === 'PAYMENT.CAPTURE.COMPLETED') {
      const oid = event.resource?.purchase_units?.[0]?.custom_id || event.resource?.custom_id;
      if (oid) await P.fulfillOrder(oid, event.resource?.id, req.io);
    }
    res.json({ received: true });
  } catch (e) { console.error('[PayPal Webhook]', e.message); res.status(500).json({ received: false }); }
});

// ══════════════════════════════════════════════════════
// FLUTTERWAVE (Mobile Money + Card)
// ══════════════════════════════════════════════════════

// GET available mobile money networks
r.get('/flutterwave/networks', authenticate, async (req, res) => {
  res.json({ success: true, networks: Object.entries(P.FW_NETWORKS).map(([code, cfg]) => ({ code, ...cfg })) });
});

// POST initiate — either direct charge (mobile money) or payment link
r.post('/flutterwave/initiate', authenticate, async (req, res) => {
  try {
    const { package_id, amount_usd, currency, phone, network_code, use_link=false, description } = req.body;
    let usd=parseFloat(amount_usd||0), coins=0, bonus=0;
    if (package_id) {
      const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
      if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
      usd=parseFloat(pkg.price_usd); coins=pkg.coins; bonus=pkg.bonus_coins||0;
    }
    // Determine currency from network or request
    const cfg = P.FW_NETWORKS[network_code];
    const cur = currency || cfg?.currency || 'RWF';
    const amt = P.toLocal(usd, cur);
    const user = await db.queryOne('SELECT email, display_name FROM users WHERE id=?', [req.userId]).catch(()=>null);
    const orderId = await newOrder(req.userId, package_id, usd, amt, cur, coins, bonus, `flutterwave_${(network_code||'card').toLowerCase()}`, 'coin_package', package_id);

    let result;
    if (!use_link && phone && network_code) {
      // Direct mobile money charge
      result = await P.fwChargeMM({ amount: amt, currency: cur, orderId, phone, networkCode: network_code, email: user?.email, name: user?.display_name });
      result.mode = 'direct';
    } else {
      // Payment link (supports card + mobile money selection page)
      result = await P.fwPaymentLink({ amount: amt, currency: cur, orderId, email: user?.email, name: user?.display_name, phone, narration: description||`RedOrrange ${coins} coins` });
      result.mode = 'link';
    }
    await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [result.flw_ref||orderId, orderId]);
    res.json({ success: true, order_id: orderId, ...result });
  } catch (e) { console.error('[FW Initiate]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// POST validate OTP/PIN
r.post('/flutterwave/validate', authenticate, async (req, res) => {
  try {
    const { flw_ref, otp, order_id, network_code } = req.body;
    if (!flw_ref || !otp) return res.status(400).json({ success: false, message: 'flw_ref and otp required' });
    const result = await P.fwValidateOtp({ flwRef: flw_ref, otp, networkCode: network_code });
    if (!result.success) return res.json({ success: false, status: result.status, message: 'Validation failed — check OTP and retry' });
    const fulfil = await P.fulfillOrder(order_id, flw_ref, req.io);
    res.json({ success: fulfil.success, ...fulfil });
  } catch (e) { console.error('[FW Validate]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// GET verify by transaction ID
r.get('/flutterwave/verify/:txId', authenticate, async (req, res) => {
  try {
    const { order_id } = req.query;
    const v = await P.fwVerifyTx(req.params.txId);
    if (v.success && order_id) {
      const f = await P.fulfillOrder(order_id, v.flw_ref, req.io);
      return res.json({ success: f.success, verified: true, ...v, ...f });
    }
    res.json({ success: false, verified: false, status: v.status });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET verify by order_id (poll order status)
r.get('/flutterwave/status', authenticate, async (req, res) => {
  try {
    const { order_id } = req.query;
    const order = await db.queryOne('SELECT status FROM payment_orders WHERE id=? AND user_id=?', [order_id, req.userId]);
    res.json({ success: true, status: order?.status || 'not_found' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// GET redirect — user returns from FW hosted page
r.get('/flutterwave/redirect', async (req, res) => {
  const { order_id, transaction_id, status } = req.query;
  const fe = process.env.FRONTEND_URL || 'https://redorrange.app';
  try {
    if (status === 'successful' && transaction_id) {
      const v = await P.fwVerifyTx(transaction_id);
      if (v.success && order_id) { await P.fulfillOrder(order_id, v.flw_ref, null); }
    }
    res.redirect(`${fe}/payment/callback?provider=flutterwave&order_id=${order_id}&status=${status}`);
  } catch (e) { res.redirect(`${fe}/payment/callback?provider=flutterwave&order_id=${order_id}&status=failed`); }
});

// POST Flutterwave Webhook
r.post('/flutterwave/webhook', async (req, res) => {
  try {
    const hash = req.headers['verif-hash'];
    if (!P.fwVerifyWebhookHash(hash) && process.env.NODE_ENV === 'production') return res.status(401).json({});
    const event = req.body;
    if (event.event === 'charge.completed' && event.data?.status === 'successful') {
      const txRef = event.data.tx_ref;
      const order = await db.queryOne("SELECT * FROM payment_orders WHERE id=? AND status='pending'", [txRef]);
      if (order) await P.fulfillOrder(txRef, event.data.flw_ref, null);
    }
    res.json({ status: 'success' });
  } catch (e) { console.error('[FW Webhook]', e.message); res.status(500).json({ status: 'error' }); }
});

// ══════════════════════════════════════════════════════
// SUBSCRIPTION PLANS
// ══════════════════════════════════════════════════════
r.get('/subscription/plans', authenticate, async (req, res) => {
  try {
    const currency = (req.query.currency||'USD').toUpperCase();
    const plans = await db.query("SELECT * FROM subscription_plans WHERE is_active=1 ORDER BY price_usd");
    plans.forEach(p => {
      p.price_local = P.toLocal(p.price_usd, currency);
      p.currency = currency; p.symbol = P.sym(currency);
      if (typeof p.features === 'string') try { p.features = JSON.parse(p.features); } catch {}
    });
    const current = await db.queryOne("SELECT us.*,sp.name plan_name,sp.features,sp.price_usd FROM user_subscriptions us JOIN subscription_plans sp ON us.plan_id=sp.id WHERE us.user_id=? AND us.status='active' AND us.expires_at>NOW()", [req.userId]);
    if (current && typeof current.features === 'string') try { current.features = JSON.parse(current.features); } catch {}
    res.json({ success: true, plans, current_subscription: current||null });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/subscription/activate', authenticate, async (req, res) => {
  try {
    const { plan_id, provider_ref, payment_method } = req.body;
    const plan = await db.queryOne('SELECT * FROM subscription_plans WHERE id=? AND is_active=1', [plan_id]);
    if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
    const exp = new Date(Date.now() + plan.duration_days * 86400000);
    await db.query(
      "INSERT INTO user_subscriptions (id,user_id,plan_id,status,expires_at,auto_renew) VALUES (?,?,?,'active',?,1) ON CONFLICT (user_id,plan_id) DO UPDATE SET status='active', expires_at=EXCLUDED.expires_at",
      [uuidv4(), req.userId, plan_id, exp]);
    // Credit monthly coins
    const features = typeof plan.features === 'string' ? JSON.parse(plan.features||'[]') : (plan.features||[]);
    const coinFeat = features.find(f => /\d+.*coins/i.test(f));
    if (coinFeat) {
      const m = coinFeat.match(/(\d+)/); if (m) {
        const c = parseInt(m[1]);
        const w = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
        const bef = w?.coins||0;
        if (!w) await db.query('INSERT INTO user_wallets (id,user_id,coins) VALUES (?,?,0)', [uuidv4(), req.userId]);
        await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [c, req.userId]);
        await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,balance_before,balance_after,reference_id,description) VALUES (?,?,?,?,?,?,?,?)',
          [uuidv4(), req.userId, 'subscription_bonus', c, bef, bef+c, plan_id, `${plan.name} monthly coins`]);
      }
    }
    if (req.io) req.io.to(`user_${req.userId}`).emit('subscription_activated', { plan_name: plan.name, expires_at: exp });
    res.json({ success: true, plan, expires_at: exp, message: `${plan.name} activated!` });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/subscription/cancel', authenticate, async (req, res) => {
  try {
    const sub = await db.queryOne("SELECT * FROM user_subscriptions WHERE user_id=? AND status='active'", [req.userId]);
    if (!sub) return res.json({ success: false, message: 'No active subscription' });
    await db.query("UPDATE user_subscriptions SET auto_renew=0,status='cancelled' WHERE user_id=?", [req.userId]);
    // If Stripe subscription, cancel it
    if (sub.stripe_subscription_id) {
      try { await P.stripeCancelSubscription ? P.stripeCancelSubscription(sub.stripe_subscription_id) : null; } catch {}
    }
    res.json({ success: true, message: 'Subscription cancelled. Access continues until expiry.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ══════════════════════════════════════════════════════
// AD BILLING (Stripe)
// ══════════════════════════════════════════════════════
r.post('/ads/topup', authenticate, async (req, res) => {
  try {
    const { amount_usd, ad_account_id, currency='USD' } = req.body;
    const amt = parseFloat(amount_usd);
    if (amt < 1) return res.status(400).json({ success: false, message: 'Minimum top-up is $1' });
    const account = await db.queryOne('SELECT id,balance_usd FROM ad_accounts WHERE id=? AND user_id=?', [ad_account_id, req.userId]);
    if (!account) return res.status(404).json({ success: false, message: 'Ad account not found' });
    const orderId = await newOrder(req.userId, null, amt, P.toLocal(amt,currency), currency, 0, 0, 'stripe', 'ad_topup', ad_account_id);
    const intent  = await P.stripeCreateIntent({ amountUsd: amt, currency, orderId, description: `RedOrrange Ads top-up $${amt}`, userId: req.userId });
    await db.query('UPDATE payment_orders SET provider_ref=? WHERE id=?', [intent.payment_intent_id, orderId]);
    res.json({ success: true, order_id: orderId, ...intent });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ══════════════════════════════════════════════════════
// UNIVERSAL CONFIRMATION
// ══════════════════════════════════════════════════════
r.post('/confirm', authenticate, async (req, res) => {
  try {
    const { payment_intent_id, order_id, paypal_order_id, flw_ref } = req.body;
    let providerRef = payment_intent_id || paypal_order_id || flw_ref;
    
    if (payment_intent_id) {
      const v = await P.stripeConfirmIntent(payment_intent_id);
      if (!v.success) return res.json({ success: false, message: `Stripe: ${v.status}` });
    } else if (paypal_order_id) {
       const cap = await P.paypalCaptureOrder(paypal_order_id);
       if (!cap.success) return res.json({ success: false, message: `PayPal: ${cap.status}` });
       providerRef = cap.capture_id;
    }
    
    if (!order_id) return res.status(400).json({ success: false, message: 'order_id required' });
    const fulfil = await P.fulfillOrder(order_id, providerRef, req.io);
    res.json({ success: fulfil.success, provider_ref: providerRef, ...fulfil });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
