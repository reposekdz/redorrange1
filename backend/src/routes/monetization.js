const express = require('express');
const r       = express.Router();
const { authenticate } = require('../middleware/auth');
const db      = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const { notify } = require('../services/notificationService');
const { stripe, paypal, flutterwave, creditCoins, completeOrder } = require('../services/paymentService');

// ════════════════════════════════════════════════════════════════
// WALLET
// ════════════════════════════════════════════════════════════════
r.get('/coins/wallet', authenticate, async (req, res) => {
  try {
    let w = await db.queryOne('SELECT * FROM user_wallets WHERE user_id=?', [req.userId]);
    if (!w) { await db.query('INSERT INTO user_wallets (id,user_id,coins) VALUES (?,?,0)', [uuidv4(), req.userId]); w = await db.queryOne('SELECT * FROM user_wallets WHERE user_id=?', [req.userId]); }
    const [txns, giftsReceived, pendingOrders] = await Promise.all([
      db.query('SELECT * FROM coin_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT 30', [req.userId]),
      db.queryOne('SELECT COALESCE(SUM(coins_spent),0) AS total FROM gift_transactions WHERE receiver_id=?', [req.userId]),
      db.query("SELECT * FROM payment_orders WHERE user_id=? AND status='pending' ORDER BY created_at DESC LIMIT 5", [req.userId]),
    ]);
    res.json({ success: true, wallet: w, transactions: txns, gifts_received_value: giftsReceived?.total || 0, pending_orders: pendingOrders });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/coins/packages', authenticate, async (req, res) => {
  try {
    const pkgs = await db.query("SELECT * FROM coin_packages WHERE is_active=1 ORDER BY price_usd");
    res.json({ success: true, packages: pkgs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════════════
// STRIPE PAYMENTS
// ════════════════════════════════════════════════════════════════

// POST /api/coins/purchase/stripe — create Stripe PaymentIntent
r.post('/coins/purchase/stripe', authenticate, async (req, res) => {
  try {
    const { package_id, currency = 'USD' } = req.body;
    if (!package_id) return res.status(400).json({ success: false, message: 'package_id required' });
    const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
    if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
    const user = await db.queryOne('SELECT id, phone_number FROM users WHERE id=?', [req.userId]);
    const orderId = uuidv4();
    const totalCoins = (pkg.coins || 0) + (pkg.bonus_coins || 0);
    await db.query(
      'INSERT INTO payment_orders (id,user_id,package_id,amount_usd,currency,coins,bonus_coins,payment_method,status) VALUES (?,?,?,?,?,?,?,?,?)',
      [orderId, req.userId, package_id, pkg.price_usd, currency, pkg.coins, pkg.bonus_coins || 0, 'stripe', 'pending']
    );
    const intent = await stripe.createPaymentIntent({
      orderId, amountUsd: parseFloat(pkg.price_usd),
      currency, userId: req.userId,
      customerEmail: user?.phone_number ? `${user.phone_number}@redorrange.app` : undefined,
      description: `${pkg.name} — ${totalCoins} coins`,
    });
    res.json({ success: true, order_id: orderId, ...intent, amount: pkg.price_usd, currency, total_coins: totalCoins, package: pkg });
  } catch (e) { console.error('[Stripe]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/coins/purchase/stripe/confirm — confirm after Flutter Stripe SDK payment
r.post('/coins/purchase/stripe/confirm', authenticate, async (req, res) => {
  try {
    const { payment_intent_id, order_id } = req.body;
    if (!payment_intent_id || !order_id) return res.status(400).json({ success: false, message: 'payment_intent_id and order_id required' });
    const result = await stripe.verifyPayment(payment_intent_id);
    if (!result.success) return res.status(400).json({ success: false, message: `Payment not succeeded: ${result.status}` });
    const order = await completeOrder(order_id, payment_intent_id, 'stripe');
    if (!order) return res.status(400).json({ success: false, message: 'Order already processed or not found' });
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    res.json({ success: true, coins_added: order.total_coins, new_balance: wallet?.coins || 0, message: `🎉 ${order.total_coins} coins added to your wallet!` });
  } catch (e) { console.error('[Stripe Confirm]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// ── Stripe subscriptions
r.post('/subscribe/stripe', authenticate, async (req, res) => {
  try {
    const { plan_id } = req.body;
    const plan = await db.queryOne('SELECT * FROM subscription_plans WHERE id=?', [plan_id]);
    if (!plan) return res.status(404).json({ success: false, message: 'Plan not found' });
    const user = await db.queryOne('SELECT id, phone_number, stripe_customer_id FROM users WHERE id=?', [req.userId]);
    const priceId = await stripe.getOrCreatePrice(plan);
    const sub = await stripe.createSubscription({
      userId: req.userId, priceId,
      customerEmail: user?.phone_number ? `${user.phone_number}@redorrange.app` : undefined,
    });
    const subId = uuidv4();
    await db.query(
      'INSERT INTO user_subscriptions (id,user_id,plan_id,status,provider,provider_subscription_id,current_period_start,current_period_end) VALUES (?,?,?,?,?,?,NOW(),NOW() + INTERVAL '30 day')',
      [subId, req.userId, plan_id, 'incomplete', 'stripe', sub.subscription_id]
    );
    res.json({ success: true, subscription_id: subId, stripe_sub_id: sub.subscription_id, client_secret: sub.client_secret, status: sub.status });
  } catch (e) { console.error('[Stripe Sub]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// ── Stripe webhook
r.post('/webhooks/stripe', express.raw({ type: 'application/json' }), async (req, res) => {
  let event;
  try {
    event = stripe.constructWebhookEvent(req.body, req.headers['stripe-signature']);
  } catch (e) { return res.status(400).json({ error: `Webhook Error: ${e.message}` }); }

  try {
    switch (event.type) {
      case 'payment_intent.succeeded': {
        const pi = event.data.object;
        const orderId = pi.metadata?.order_id;
        if (orderId) {
          const order = await completeOrder(orderId, pi.id, 'stripe');
          if (order) await notify(null, { userId: order.user_id, type: 'payment_success', message: `✅ Payment of $${pi.amount / 100} received — ${order.total_coins} coins added!`, targetType: 'wallet', targetId: orderId });
        }
        break;
      }
      case 'payment_intent.payment_failed': {
        const pi = event.data.object;
        if (pi.metadata?.order_id) await db.query("UPDATE payment_orders SET status='failed' WHERE id=?", [pi.metadata.order_id]);
        break;
      }
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        const status = event.type === 'customer.subscription.deleted' ? 'cancelled' : (sub.status === 'active' ? 'active' : sub.status);
        await db.query("UPDATE user_subscriptions SET status=? WHERE provider_subscription_id=?", [status, sub.id]);
        break;
      }
      case 'invoice.paid': {
        const inv = event.data.object;
        await db.query("UPDATE user_subscriptions SET status='active', current_period_start=FROM_UNIXTIME(?), current_period_end=FROM_UNIXTIME(?) WHERE provider_subscription_id=?",
          [inv.period_start, inv.period_end, inv.subscription]);
        break;
      }
    }
    res.json({ received: true });
  } catch (e) { console.error('[Stripe Webhook]', e.message); res.status(200).json({ received: true }); }
});

// ════════════════════════════════════════════════════════════════
// PAYPAL PAYMENTS
// ════════════════════════════════════════════════════════════════

// POST /api/coins/purchase/paypal — create PayPal order
r.post('/coins/purchase/paypal', authenticate, async (req, res) => {
  try {
    const { package_id, currency = 'USD' } = req.body;
    const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
    if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
    const totalCoins = (pkg.coins || 0) + (pkg.bonus_coins || 0);
    const orderId = uuidv4();
    await db.query(
      'INSERT INTO payment_orders (id,user_id,package_id,amount_usd,currency,coins,bonus_coins,payment_method,status) VALUES (?,?,?,?,?,?,?,?,?)',
      [orderId, req.userId, package_id, pkg.price_usd, currency, pkg.coins, pkg.bonus_coins || 0, 'paypal', 'pending']
    );
    const ppOrder = await paypal.createOrder({ orderId, amountUsd: parseFloat(pkg.price_usd), currency, description: `RedOrrange — ${pkg.name} (${totalCoins} coins)` });
    await db.query("UPDATE payment_orders SET provider_ref=? WHERE id=?", [ppOrder.paypal_order_id, orderId]);
    res.json({ success: true, order_id: orderId, paypal_order_id: ppOrder.paypal_order_id, approve_url: ppOrder.approve_url, amount: pkg.price_usd, currency, total_coins: totalCoins, package: pkg });
  } catch (e) { console.error('[PayPal]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/coins/purchase/paypal/capture — capture after approval
r.post('/coins/purchase/paypal/capture', authenticate, async (req, res) => {
  try {
    const { paypal_order_id, order_id } = req.body;
    const result = await paypal.captureOrder(paypal_order_id);
    if (!result.success) return res.status(400).json({ success: false, message: `PayPal capture failed: ${result.status}` });
    const order = await completeOrder(order_id, result.paypal_txn_id, 'paypal');
    if (!order) return res.status(400).json({ success: false, message: 'Order already processed' });
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    res.json({ success: true, coins_added: order.total_coins, new_balance: wallet?.coins || 0, message: `🎉 ${order.total_coins} coins added!` });
  } catch (e) { console.error('[PayPal Cap]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// ── PayPal webhook
r.post('/webhooks/paypal', async (req, res) => {
  const verified = await paypal.verifyWebhook({ headers: req.headers, body: req.body });
  if (!verified) return res.status(401).json({ error: 'Invalid signature' });
  try {
    const { event_type, resource } = req.body;
    if (event_type === 'PAYMENT.CAPTURE.COMPLETED') {
      const orderId = resource?.supplementary_data?.related_ids?.order_id || resource?.custom_id;
      if (orderId) {
        const order = await db.queryOne("SELECT * FROM payment_orders WHERE provider_ref=? OR id=?", [resource.id, orderId]);
        if (order && order.status === 'pending') {
          await completeOrder(order.id, resource.id, 'paypal');
          await notify(null, { userId: order.user_id, type: 'payment_success', message: `✅ PayPal payment confirmed — coins added!` });
        }
      }
    }
    res.json({ received: true });
  } catch (e) { console.error('[PayPal WH]', e.message); res.status(200).json({ received: true }); }
});

// ════════════════════════════════════════════════════════════════
// FLUTTERWAVE PAYMENTS (Africa — Mobile Money + Card)
// ════════════════════════════════════════════════════════════════

// POST /api/coins/purchase/flutterwave — initiate standard checkout
r.post('/coins/purchase/flutterwave', authenticate, async (req, res) => {
  try {
    const { package_id, currency = 'RWF', email, phone, name = 'RedOrrange User', payment_type = 'card' } = req.body;
    const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
    if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
    const totalCoins = (pkg.coins || 0) + (pkg.bonus_coins || 0);
    const amount = currency === 'RWF' ? Math.round(parseFloat(pkg.price_usd) * 1220) : parseFloat(pkg.price_usd);
    const orderId = uuidv4();
    await db.query(
      'INSERT INTO payment_orders (id,user_id,package_id,amount_usd,amount_local,currency,coins,bonus_coins,payment_method,status) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [orderId, req.userId, package_id, pkg.price_usd, amount, currency, pkg.coins, pkg.bonus_coins || 0, 'flutterwave', 'pending']
    );
    const init = await flutterwave.initializePayment({ orderId, amountUsd: parseFloat(pkg.price_usd), currency, email: email || `user${req.userId}@redorrange.app`, phone, name, paymentType: payment_type });
    await db.query("UPDATE payment_orders SET provider_ref=? WHERE id=?", [init.tx_ref, orderId]);
    res.json({ success: true, order_id: orderId, payment_link: init.link, tx_ref: init.tx_ref, amount, currency, total_coins: totalCoins, package: pkg });
  } catch (e) { console.error('[FLW]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/coins/purchase/flutterwave/mobile-money — direct mobile money charge
r.post('/coins/purchase/flutterwave/mobile-money', authenticate, async (req, res) => {
  try {
    const { package_id, phone, network = 'mtn_rw', email, name, currency = 'RWF' } = req.body;
    if (!phone || !network) return res.status(400).json({ success: false, message: 'phone and network required' });
    const pkg = await db.queryOne('SELECT * FROM coin_packages WHERE id=? AND is_active=1', [package_id]);
    if (!pkg) return res.status(404).json({ success: false, message: 'Package not found' });
    const totalCoins = (pkg.coins || 0) + (pkg.bonus_coins || 0);
    const amount = currency === 'RWF' ? Math.round(parseFloat(pkg.price_usd) * 1220) : parseFloat(pkg.price_usd);
    const orderId = uuidv4();
    await db.query(
      'INSERT INTO payment_orders (id,user_id,package_id,amount_usd,amount_local,currency,coins,bonus_coins,payment_method,status) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [orderId, req.userId, package_id, pkg.price_usd, amount, currency, pkg.coins, pkg.bonus_coins || 0, `flutterwave_${network}`, 'pending']
    );
    const charge = await flutterwave.chargeMobileMoney({
      orderId, amount, currency, phone, network, email: email || `${phone}@redorrange.app`, name: name || 'User',
    });
    await db.query("UPDATE payment_orders SET provider_ref=? WHERE id=?", [charge.tx_ref, orderId]);
    res.json({ success: true, order_id: orderId, tx_ref: charge.tx_ref, flw_ref: charge.flw_ref, status: charge.status, amount, currency, total_coins: totalCoins, message: `Check your ${network.toUpperCase().replace('_RW','').replace('_RW','')} phone for payment prompt`, package: pkg });
  } catch (e) { console.error('[FLW MM]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// POST /api/coins/purchase/flutterwave/verify — verify and credit after payment
r.post('/coins/purchase/flutterwave/verify', authenticate, async (req, res) => {
  try {
    const { tx_ref, order_id } = req.body;
    const result = await flutterwave.verifyTransaction(tx_ref);
    if (!result.success) return res.status(400).json({ success: false, message: `Payment not successful: ${result.status}`, status: result.status });
    const order = await completeOrder(order_id, result.flw_txn_id?.toString(), 'flutterwave');
    if (!order) return res.status(400).json({ success: false, message: 'Order already processed or not found' });
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    res.json({ success: true, coins_added: order.total_coins, new_balance: wallet?.coins || 0, message: `🎉 ${order.total_coins} coins added to your wallet!` });
  } catch (e) { console.error('[FLW Verify]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// GET /api/coins/purchase/flutterwave/banks — supported banks
r.get('/coins/purchase/flutterwave/banks', authenticate, async (req, res) => {
  try {
    const { country = 'RW' } = req.query;
    const banks = await flutterwave.getBanks(country);
    res.json({ success: true, banks });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Flutterwave webhook
r.post('/webhooks/flutterwave', async (req, res) => {
  if (!flutterwave.verifyWebhook(req)) return res.status(401).json({ error: 'Invalid signature' });
  try {
    const { event, data } = req.body;
    if (event === 'charge.completed' && data.status === 'successful') {
      const orderId = data.meta?.order_id;
      if (orderId) {
        const order = await db.queryOne("SELECT * FROM payment_orders WHERE provider_ref=? AND status='pending'", [data.tx_ref]);
        if (order) {
          await completeOrder(order.id, data.id?.toString(), 'flutterwave');
          await notify(null, { userId: order.user_id, type: 'payment_success', message: `✅ Mobile money payment confirmed — coins added!` });
        }
      }
    }
    res.json({ status: 'success' });
  } catch (e) { console.error('[FLW WH]', e.message); res.status(200).json({ status: 'success' }); }
});

// ── Redirect handler (after PayPal/Flutterwave redirect back)
r.get('/payment/callback', async (req, res) => {
  const { order_id, tx_ref, PayerID, token } = req.query;
  const gateway = req.query.gateway || (PayerID ? 'paypal' : 'flutterwave');
  if (gateway === 'paypal' && token && order_id) {
    try {
      const result = await paypal.captureOrder(token);
      if (result.success && order_id) {
        const order = await db.queryOne("SELECT * FROM payment_orders WHERE id=? AND status='pending'", [order_id]);
        if (order) await completeOrder(order_id, result.paypal_txn_id, 'paypal');
      }
    } catch (e) { console.error('[PayPal redirect]', e.message); }
  }
  // Redirect to app deep link or web success page
  res.redirect(`${process.env.FRONTEND_URL || 'https://redorrange.app'}/payment-success?order_id=${order_id || ''}&gateway=${gateway}`);
});

// ════════════════════════════════════════════════════════════════
// COINS — GIFTING & LIVE
// ════════════════════════════════════════════════════════════════
r.get('/gifts', authenticate, async (req, res) => {
  try {
    const gifts = await db.query("SELECT * FROM gifts WHERE is_active=1 ORDER BY coin_cost");
    res.json({ success: true, gifts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/gifts/send', authenticate, async (req, res) => {
  try {
    const { gift_id, receiver_id, stream_id } = req.body;
    if (!gift_id || !receiver_id) return res.status(400).json({ success: false, message: 'gift_id and receiver_id required' });
    const [gift, wallet] = await Promise.all([
      db.queryOne('SELECT * FROM gifts WHERE id=? AND is_active=1', [gift_id]),
      db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]),
    ]);
    if (!gift) return res.status(404).json({ success: false, message: 'Gift not found' });
    if (!wallet || wallet.coins < gift.coin_cost) return res.status(400).json({ success: false, message: 'Insufficient coins' });
    const receiverCoins = Math.floor(gift.coin_cost * 0.7); // 70% to receiver
    const platformFee   = gift.coin_cost - receiverCoins;   // 30% platform
    const txId = uuidv4();
    await db.query('UPDATE user_wallets SET coins=coins-? WHERE user_id=?', [gift.coin_cost, req.userId]);
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [receiverCoins, receiver_id]);
    await db.query('INSERT INTO gift_transactions (id,sender_id,receiver_id,gift_id,stream_id,coins_spent,receiver_coins,platform_fee) VALUES (?,?,?,?,?,?,?,?)',
      [txId, req.userId, receiver_id, gift_id, stream_id || null, gift.coin_cost, receiverCoins, platformFee]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,description,reference_id) VALUES (?,?,?,?,?,?)',
      [uuidv4(), req.userId, 'gift_sent', -gift.coin_cost, `Sent ${gift.name} gift`, txId]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,description,reference_id) VALUES (?,?,?,?,?,?)',
      [uuidv4(), receiver_id, 'gift_received', receiverCoins, `Received ${gift.name} gift`, txId]);
    const newBalance = (wallet.coins || 0) - gift.coin_cost;
    if (req.io && stream_id) req.io.to(`live_${stream_id}`).emit('live_gift', { sender: { id: req.userId }, gift, stream_id, sent_at: new Date().toISOString() });
    await notify(req.io, { userId: receiver_id, actorId: req.userId, type: 'gift', targetType: 'gift', targetId: txId, message: `Sent you a ${gift.emoji} ${gift.name} gift!` });
    res.json({ success: true, gift, coins_spent: gift.coin_cost, receiver_coins: receiverCoins, new_balance: newBalance });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════════════
// SUBSCRIPTIONS
// ════════════════════════════════════════════════════════════════
r.get('/subscription/plans', authenticate, async (req, res) => {
  try {
    const [plans, current] = await Promise.all([
      db.query("SELECT * FROM subscription_plans WHERE is_active=1 ORDER BY price_usd"),
      db.queryOne("SELECT s.*, p.name AS plan_name, p.features FROM user_subscriptions s JOIN subscription_plans p ON s.plan_id=p.id WHERE s.user_id=? AND s.status='active' ORDER BY s.created_at DESC LIMIT 1", [req.userId]),
    ]);
    plans.forEach(p => { try { p.features = JSON.parse(p.features); } catch { p.features = []; } });
    res.json({ success: true, plans, current_subscription: current || null });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/subscription/current', authenticate, async (req, res) => {
  try {
    const sub = await db.queryOne("SELECT s.*, p.name AS plan_name, p.features, p.monthly_coins FROM user_subscriptions s JOIN subscription_plans p ON s.plan_id=p.id WHERE s.user_id=? AND s.status='active' ORDER BY s.created_at DESC LIMIT 1", [req.userId]);
    res.json({ success: true, subscription: sub || null });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/subscription/cancel', authenticate, async (req, res) => {
  try {
    const sub = await db.queryOne("SELECT * FROM user_subscriptions WHERE user_id=? AND status='active'", [req.userId]);
    if (!sub) return res.status(404).json({ success: false, message: 'No active subscription' });
    if (sub.provider === 'stripe' && sub.provider_subscription_id) await stripe.cancelSubscription(sub.provider_subscription_id).catch(() => {});
    await db.query("UPDATE user_subscriptions SET status='cancelled', cancelled_at=NOW() WHERE id=?", [sub.id]);
    res.json({ success: true, message: 'Subscription cancelled. Access continues until period end.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════════════
// AD ACCOUNT BILLING
// ════════════════════════════════════════════════════════════════
r.post('/ads/accounts/:id/topup/stripe', authenticate, async (req, res) => {
  try {
    const { amount } = req.body;
    if (!amount || amount < 1) return res.status(400).json({ success: false, message: 'Minimum $1' });
    const account = await db.queryOne('SELECT * FROM ad_accounts WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    if (!account) return res.status(404).json({ success: false });
    const orderId = uuidv4();
    const intent = await stripe.createPaymentIntent({ orderId, amountUsd: parseFloat(amount), currency: 'usd', userId: req.userId, description: `Ad Account Top-up $${amount}` });
    await db.query('INSERT INTO ad_billing (id,account_id,type,amount,balance_before,balance_after,description,payment_method) VALUES (?,?,?,?,?,?,?,?)',
      [orderId, account.id, 'topup_pending', amount, account.balance_usd, account.balance_usd, `Ad account top-up (pending)`, 'stripe']);
    res.json({ success: true, ...intent, order_id: orderId, amount });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/ads/accounts/:id/topup/stripe/confirm', authenticate, async (req, res) => {
  try {
    const { payment_intent_id, order_id, amount } = req.body;
    const result = await stripe.verifyPayment(payment_intent_id);
    if (!result.success) return res.status(400).json({ success: false, message: 'Payment not succeeded' });
    const account = await db.queryOne('SELECT * FROM ad_accounts WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    const newBal = parseFloat(account.balance_usd) + parseFloat(amount);
    await db.query('UPDATE ad_accounts SET balance_usd=? WHERE id=?', [newBal, account.id]);
    await db.query('UPDATE ad_billing SET type=?,balance_after=?,payment_ref=? WHERE id=?', ['topup', newBal, payment_intent_id, order_id]);
    res.json({ success: true, new_balance: newBal });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════════════
// PAYOUTS (Creator → Bank/Mobile Money via Flutterwave)
// ════════════════════════════════════════════════════════════════
r.get('/payouts/balance', authenticate, async (req, res) => {
  try {
    const wallet = await db.queryOne('SELECT * FROM user_wallets WHERE user_id=?', [req.userId]);
    const pending = await db.queryOne("SELECT COALESCE(SUM(amount_usd),0) AS total FROM creator_payouts WHERE user_id=? AND status='pending'", [req.userId]);
    const usdBalance = ((wallet?.coins || 0) / 100) * 0.50; // 100 coins = $0.50
    res.json({ success: true, coins: wallet?.coins || 0, usd_value: usdBalance.toFixed(2), minimum_payout: 5.00, pending_payout: pending?.total || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/payouts/history', authenticate, async (req, res) => {
  try {
    const payouts = await db.query('SELECT * FROM creator_payouts WHERE user_id=? ORDER BY created_at DESC LIMIT 20', [req.userId]);
    res.json({ success: true, payouts });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/payouts/request', authenticate, async (req, res) => {
  try {
    const { coins_to_cash, method, phone, network, bank_code, account_number, account_name, currency = 'RWF', country = 'RW' } = req.body;
    if (!coins_to_cash || coins_to_cash < 1000) return res.status(400).json({ success: false, message: 'Minimum 1,000 coins to cash out' });
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    if (!wallet || wallet.coins < coins_to_cash) return res.status(400).json({ success: false, message: 'Insufficient coins' });
    const amountUsd = (coins_to_cash / 100) * 0.50;
    const amountLocal = currency === 'RWF' ? Math.floor(amountUsd * 1220) : amountUsd;
    if (amountUsd < 5) return res.status(400).json({ success: false, message: 'Minimum payout is $5 (1,000 coins)' });
    const payoutId = uuidv4();
    await db.query('UPDATE user_wallets SET coins=coins-? WHERE user_id=?', [coins_to_cash, req.userId]);
    await db.query('INSERT INTO creator_payouts (id,user_id,coins_cashed,amount_usd,amount_local,currency,method,phone,network,bank_code,account_number,account_name,status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [payoutId, req.userId, coins_to_cash, amountUsd, amountLocal, currency, method || 'mobile_money', phone || null, network || null, bank_code || null, account_number || null, account_name || null, 'pending']);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,description,reference_id) VALUES (?,?,?,?,?,?)',
      [uuidv4(), req.userId, 'payout', -coins_to_cash, `Payout request — $${amountUsd.toFixed(2)}`, payoutId]);

    // Initiate Flutterwave transfer immediately
    let transferResult = null;
    try {
      transferResult = await flutterwave.initiatePayout({
        userId: req.userId, amount: amountLocal, currency,
        phone, network: network || 'mtn_rw',
        bankCode: bank_code, accountNumber: account_number,
        narration: `RedOrrange payout — ${coins_to_cash} coins`,
      });
      if (transferResult?.transfer_id) {
        await db.query("UPDATE creator_payouts SET status='processing', provider_ref=? WHERE id=?", [transferResult.transfer_id?.toString(), payoutId]);
      }
    } catch (flwErr) { console.error('[Payout FLW]', flwErr.message); }

    await notify(req.io, { userId: req.userId, type: 'payout_initiated', message: `💰 Payout of ${amountLocal} ${currency} initiated — expect within 1-3 business days` });
    res.json({ success: true, payout_id: payoutId, amount_usd: amountUsd, amount_local: amountLocal, currency, coins_cashed: coins_to_cash, status: transferResult ? 'processing' : 'pending', message: `Payout of ${amountLocal} ${currency} initiated. Arrives within 1-3 business days.` });
  } catch (e) { console.error('[Payout]', e.message); res.status(500).json({ success: false, message: e.message }); }
});

// GET supported payout methods
r.get('/payouts/methods', authenticate, async (req, res) => {
  res.json({ success: true, methods: [
    { id: 'mobile_money', name: 'Mobile Money', icon: 'phone_android', networks: [
      { id: 'mtn_rw', name: 'MTN Rwanda', flag: '🇷🇼', currency: 'RWF' },
      { id: 'airtel_rw', name: 'Airtel Rwanda', flag: '🇷🇼', currency: 'RWF' },
      { id: 'mpesa', name: 'M-Pesa Kenya', flag: '🇰🇪', currency: 'KES' },
      { id: 'mtn_ug', name: 'MTN Uganda', flag: '🇺🇬', currency: 'UGX' },
      { id: 'airtel_ug', name: 'Airtel Uganda', flag: '🇺🇬', currency: 'UGX' },
    ]},
    { id: 'bank_transfer', name: 'Bank Transfer', icon: 'account_balance', currencies: ['RWF', 'USD', 'KES', 'UGX'] },
    { id: 'paypal', name: 'PayPal', icon: 'payment', currencies: ['USD'] },
  ]});
});

// ════════════════════════════════════════════════════════════════
// ESCROW
// ════════════════════════════════════════════════════════════════
r.get('/escrow', authenticate, async (req, res) => {
  try {
    const [buying, selling] = await Promise.all([
      db.query(`SELECT e.*, m.title AS item_title, m.cover_url AS item_img, u.username AS seller_name, u.avatar_url AS seller_avatar FROM escrow_orders e JOIN marketplace_items m ON e.item_id=m.id JOIN users u ON e.seller_id=u.id WHERE e.buyer_id=? ORDER BY e.created_at DESC`, [req.userId]),
      db.query(`SELECT e.*, m.title AS item_title, m.cover_url AS item_img, u.username AS buyer_name, u.avatar_url AS buyer_avatar FROM escrow_orders e JOIN marketplace_items m ON e.item_id=m.id JOIN users u ON e.buyer_id=u.id WHERE e.seller_id=? ORDER BY e.created_at DESC`, [req.userId]),
    ]);
    res.json({ success: true, buying, selling });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/escrow/:id/fund', authenticate, async (req, res) => {
  try {
    const order = await db.queryOne("SELECT * FROM escrow_orders WHERE id=? AND buyer_id=? AND status='created'", [req.params.id, req.userId]);
    if (!order) return res.status(404).json({ success: false, message: 'Order not found' });
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    if (!wallet || wallet.coins < order.coins_amount) return res.status(400).json({ success: false, message: 'Insufficient coins. Buy more in Wallet.' });
    await db.query('UPDATE user_wallets SET coins=coins-? WHERE user_id=?', [order.coins_amount, req.userId]);
    await db.query("UPDATE escrow_orders SET status='funded', funded_at=NOW() WHERE id=?", [req.params.id]);
    await db.query('INSERT INTO escrow_events (id,order_id,actor_id,event_type,notes) VALUES (?,?,?,?,?)', [uuidv4(), req.params.id, req.userId, 'funded', `Buyer funded ${order.coins_amount} coins`]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,description,reference_id) VALUES (?,?,?,?,?,?)', [uuidv4(), req.userId, 'escrow_funded', -order.coins_amount, `Escrow funded for ${order.item_title || 'item'}`, req.params.id]);
    await notify(req.io, { userId: order.seller_id, actorId: req.userId, type: 'escrow_funded', message: '💰 Buyer funded escrow — ship the item now!', targetType: 'escrow', targetId: req.params.id });
    res.json({ success: true, message: 'Escrow funded! Seller has been notified to ship.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/escrow/:id/ship', authenticate, async (req, res) => {
  try {
    const { tracking_number, carrier } = req.body;
    const order = await db.queryOne("SELECT * FROM escrow_orders WHERE id=? AND seller_id=? AND status='funded'", [req.params.id, req.userId]);
    if (!order) return res.status(404).json({ success: false, message: 'Order not found or not funded' });
    await db.query("UPDATE escrow_orders SET status='shipped', tracking_number=?, shipped_at=NOW() WHERE id=?", [tracking_number || null, req.params.id]);
    await db.query('INSERT INTO escrow_events (id,order_id,actor_id,event_type,notes) VALUES (?,?,?,?,?)', [uuidv4(), req.params.id, req.userId, 'shipped', `Tracking: ${tracking_number || 'N/A'} via ${carrier || 'unknown'}`]);
    await notify(req.io, { userId: order.buyer_id, actorId: req.userId, type: 'escrow_shipped', message: `📦 Item shipped! Tracking: ${tracking_number || 'N/A'}`, targetType: 'escrow', targetId: req.params.id });
    res.json({ success: true, message: 'Marked as shipped. Buyer will confirm receipt.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/escrow/:id/confirm', authenticate, async (req, res) => {
  try {
    const order = await db.queryOne("SELECT * FROM escrow_orders WHERE id=? AND buyer_id=? AND status='shipped'", [req.params.id, req.userId]);
    if (!order) return res.status(404).json({ success: false, message: 'Order not found or not shipped yet' });
    const platformFee   = Math.ceil(order.coins_amount * 0.05);
    const sellerCoins   = order.coins_amount - platformFee;
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [sellerCoins, order.seller_id]);
    await db.query("UPDATE escrow_orders SET status='completed', completed_at=NOW() WHERE id=?", [req.params.id]);
    await db.query('INSERT INTO escrow_events (id,order_id,actor_id,event_type,notes) VALUES (?,?,?,?,?)', [uuidv4(), req.params.id, req.userId, 'completed', `Buyer confirmed. Seller received ${sellerCoins} coins.`]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,description,reference_id) VALUES (?,?,?,?,?,?)', [uuidv4(), order.seller_id, 'escrow_released', sellerCoins, `Sale completed — ${sellerCoins} coins released`, req.params.id]);
    await notify(req.io, { userId: order.seller_id, actorId: req.userId, type: 'escrow_completed', message: `✅ Sale complete! ${sellerCoins} coins added to your wallet.`, targetType: 'escrow', targetId: req.params.id });
    res.json({ success: true, seller_coins: sellerCoins, platform_fee: platformFee, message: 'Purchase confirmed! Seller has been paid.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/escrow/:id/dispute', authenticate, async (req, res) => {
  try {
    const { reason } = req.body;
    const order = await db.queryOne("SELECT * FROM escrow_orders WHERE id=? AND (buyer_id=? OR seller_id=?) AND status IN ('funded','shipped')", [req.params.id, req.userId, req.userId]);
    if (!order) return res.status(404).json({ success: false });
    await db.query("UPDATE escrow_orders SET status='disputed', disputed_at=NOW(), dispute_reason=? WHERE id=?", [reason || null, req.params.id]);
    await db.query('INSERT INTO escrow_events (id,order_id,actor_id,event_type,notes) VALUES (?,?,?,?,?)', [uuidv4(), req.params.id, req.userId, 'disputed', reason || 'Dispute opened']);
    const otherId = order.buyer_id === req.userId ? order.seller_id : order.buyer_id;
    await notify(req.io, { userId: otherId, actorId: req.userId, type: 'escrow_disputed', message: '⚠️ Escrow dispute opened. Our team will review within 48 hours.', targetType: 'escrow', targetId: req.params.id });
    res.json({ success: true, message: 'Dispute opened. Our team will review within 48 hours and mediate.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;

// ── PAYMENT ROUTE ALIASES (for frontend compatibility)
// The frontend calls /api/payments/* — map to correct handlers
r.post('/payments/stripe/intent',          authenticate, (req, res, next) => { req.url = '/coins/purchase/stripe'; next(); });
r.post('/payments/stripe/confirm',         authenticate, async (req, res) => {
  try {
    const { payment_intent_id, order_id } = req.body;
    const { stripeConfirmIntent, fulfillOrder } = require('../services/paymentService');
    const result = await stripeConfirmIntent(payment_intent_id);
    if (!result.success) return res.json({ success: false, message: `Payment ${result.status}` });
    const ful = await fulfillOrder(order_id, payment_intent_id, req.io);
    res.json({ success: true, ...ful });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
r.post('/payments/paypal/create',          authenticate, (req, res, next) => { req.body.package_id = req.body.package_id; next(); });
r.post('/payments/paypal/capture',         authenticate, async (req, res) => {
  try {
    const { paypal_order_id, order_id } = req.body;
    const { paypalCaptureOrder, fulfillOrder } = require('../services/paymentService');
    const result = await paypalCaptureOrder(paypal_order_id);
    if (!result.success) return res.json({ success: false, message: 'PayPal payment not completed' });
    const ful = await fulfillOrder(order_id, result.capture_id, req.io);
    res.json({ success: true, ...ful });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
r.post('/payments/flutterwave/initiate',   authenticate, (req, res, next) => next());
r.post('/payments/flutterwave/validate',   authenticate, async (req, res) => {
  try {
    const { flw_ref, otp, order_id, network_code } = req.body;
    const { fwValidateOtp, fulfillOrder } = require('../services/paymentService');
    const result = await fwValidateOtp({ flwRef: flw_ref, otp, networkCode: network_code || 'MTN_RW' });
    if (!result.success) return res.json({ success: false, message: 'OTP validation failed' });
    const ful = await fulfillOrder(order_id, result.flw_ref, req.io);
    res.json({ success: true, ...ful });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
r.get('/payments/flutterwave/status',      authenticate, async (req, res) => {
  try {
    const { order_id } = req.query;
    const order = await db.queryOne('SELECT * FROM payment_orders WHERE id=? AND user_id=?', [order_id, req.userId]);
    if (!order) return res.json({ success: false, status: 'not_found' });
    res.json({ success: true, status: order.status, coins_added: order.coins + order.bonus_coins, flw_ref: order.provider_ref, new_balance: (await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]))?.coins || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
r.get('/payments/wallet',                  authenticate, async (req, res, next) => {
  // Alias for /coins/wallet
  req.url = '/coins/wallet'; next();
});
r.get('/payments/packages',                authenticate, async (req, res) => {
  try {
    const pkgs = await db.query('SELECT * FROM coin_packages WHERE is_active=1 ORDER BY price_usd');
    res.json({ success: true, packages: pkgs });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
