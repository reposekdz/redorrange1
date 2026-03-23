'use strict';
const axios  = require('axios');
const crypto = require('crypto');
const db     = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ── STRIPE
let _stripe = null;
function stripe() {
  if (!_stripe) { _stripe = require('stripe')(process.env.STRIPE_SECRET_KEY, { apiVersion: '2024-06-20' }); }
  return _stripe;
}

async function stripeCreateIntent({ amountUsd, currency, orderId, description, userId }) {
  const cents = Math.round(parseFloat(amountUsd) * 100);
  const user  = await db.queryOne('SELECT email, display_name, stripe_customer_id FROM users WHERE id=?', [userId]).catch(()=>null);
  let custId  = user?.stripe_customer_id;
  if (!custId && user?.email) {
    const c = await stripe().customers.create({ email: user.email, name: user.display_name || undefined, metadata: { user_id: userId } });
    custId = c.id;
    await db.query('UPDATE users SET stripe_customer_id=? WHERE id=?', [c.id, userId]).catch(()=>{});
  }
  const intent = await stripe().paymentIntents.create({
    amount: cents, currency: (currency||'usd').toLowerCase(),
    customer: custId||undefined, description,
    metadata: { order_id: orderId, user_id: userId },
    automatic_payment_methods: { enabled: true },
    receipt_email: user?.email||undefined,
  });
  return { client_secret: intent.client_secret, payment_intent_id: intent.id, publishable_key: process.env.STRIPE_PUBLISHABLE_KEY, amount_cents: cents };
}

async function stripeConfirmIntent(piId) {
  const pi = await stripe().paymentIntents.retrieve(piId);
  return { success: pi.status === 'succeeded', status: pi.status };
}

function stripeVerifyWebhook(body, sig) {
  return stripe().webhooks.constructEvent(body, sig, process.env.STRIPE_WEBHOOK_SECRET);
}

async function stripeCreateSubscription({ userId, stripePriceId }) {
  const user = await db.queryOne('SELECT email, display_name, stripe_customer_id FROM users WHERE id=?', [userId]);
  let custId = user?.stripe_customer_id;
  if (!custId) {
    const c = await stripe().customers.create({ email: user.email, name: user.display_name, metadata: { user_id: userId } });
    custId = c.id;
    await db.query('UPDATE users SET stripe_customer_id=? WHERE id=?', [c.id, userId]);
  }
  const sub = await stripe().subscriptions.create({
    customer: custId, items: [{ price: stripePriceId }],
    payment_behavior: 'default_incomplete',
    payment_settings: { save_default_payment_method: 'on_subscription' },
    expand: ['latest_invoice.payment_intent'],
  });
  return { subscription_id: sub.id, client_secret: sub.latest_invoice?.payment_intent?.client_secret||null, publishable_key: process.env.STRIPE_PUBLISHABLE_KEY, status: sub.status };
}

// ── PAYPAL
let _ppTok = null, _ppExp = 0;
const ppBase = () => (process.env.PAYPAL_MODE||'sandbox')==='live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com';
async function ppToken() {
  if (_ppTok && Date.now() < _ppExp) return _ppTok;
  const r = await axios.post(`${ppBase()}/v1/oauth2/token`, 'grant_type=client_credentials', { auth: { username: process.env.PAYPAL_CLIENT_ID, password: process.env.PAYPAL_CLIENT_SECRET }, headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
  _ppTok = r.data.access_token; _ppExp = Date.now() + (r.data.expires_in-60)*1000; return _ppTok;
}
const ppH = tok => ({ Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json', Prefer: 'return=representation' });

async function paypalCreateOrder({ amountUsd, currency, orderId, description }) {
  const tok = await ppToken();
  const rUrl = `${process.env.REDIRECT_URL||'https://redorrange.app'}/payment/callback?provider=paypal&order_id=${orderId}&status=success`;
  const cUrl = `${process.env.REDIRECT_URL||'https://redorrange.app'}/payment/callback?provider=paypal&order_id=${orderId}&status=cancel`;
  const r = await axios.post(`${ppBase()}/v2/checkout/orders`, {
    intent: 'CAPTURE',
    purchase_units: [{ reference_id: orderId, custom_id: orderId, description: description||'RedOrrange', amount: { currency_code: (currency||'USD').toUpperCase(), value: parseFloat(amountUsd).toFixed(2) } }],
    payment_source: { paypal: { experience_context: { brand_name: 'RedOrrange', locale: 'en-US', landing_page: 'LOGIN', shipping_preference: 'NO_SHIPPING', user_action: 'PAY_NOW', return_url: rUrl, cancel_url: cUrl } } },
  }, { headers: { ...ppH(tok), 'PayPal-Request-Id': orderId } });
  const approveUrl = r.data.links?.find(l => ['approve','payer-action'].includes(l.rel))?.href;
  return { paypal_order_id: r.data.id, approve_url: approveUrl, status: r.data.status };
}

async function paypalCaptureOrder(ppOrderId) {
  const tok = await ppToken();
  const r = await axios.post(`${ppBase()}/v2/checkout/orders/${ppOrderId}/capture`, {}, { headers: { ...ppH(tok), 'PayPal-Request-Id': uuidv4() } });
  const unit = r.data.purchase_units?.[0]; const cap = unit?.payments?.captures?.[0];
  return { success: r.data.status==='COMPLETED', status: r.data.status, capture_id: cap?.id, amount: parseFloat(cap?.amount?.value||0), custom_id: unit?.custom_id||unit?.reference_id, payer_email: r.data.payer?.email_address };
}

async function paypalVerifyWebhook(headers, body) {
  try {
    const tok = await ppToken();
    const r = await axios.post(`${ppBase()}/v1/notifications/verify-webhook-signature`, {
      auth_algo: headers['paypal-auth-algo'], cert_url: headers['paypal-cert-url'],
      transmission_id: headers['paypal-transmission-id'], transmission_sig: headers['paypal-transmission-sig'],
      transmission_time: headers['paypal-transmission-time'],
      webhook_id: process.env.PAYPAL_WEBHOOK_ID||'PLACEHOLDER',
      webhook_event: typeof body==='string' ? JSON.parse(body) : body,
    }, { headers: ppH(tok) });
    return r.data.verification_status === 'SUCCESS';
  } catch { return process.env.NODE_ENV !== 'production'; }
}

// ── FLUTTERWAVE v3
const FW_NETWORKS = {
  MTN_RW:    { type: 'mobilemoneyrwanda',   network: 'MTN',    currency: 'RWF', country: 'RW', name: 'MTN Rwanda',      flag: '🇷🇼' },
  AIRTEL_RW: { type: 'mobilemoneyrwanda',   network: 'AIRTEL', currency: 'RWF', country: 'RW', name: 'Airtel Rwanda',   flag: '🇷🇼' },
  MPESA_KE:  { type: 'mpesa',               network: 'MPESA',  currency: 'KES', country: 'KE', name: 'M-Pesa Kenya',    flag: '🇰🇪' },
  MTN_UG:    { type: 'mobilemoneyuganda',   network: 'MTN',    currency: 'UGX', country: 'UG', name: 'MTN Uganda',      flag: '🇺🇬' },
  AIRTEL_UG: { type: 'mobilemoneyuganda',   network: 'AIRTEL', currency: 'UGX', country: 'UG', name: 'Airtel Uganda',   flag: '🇺🇬' },
  MTN_GH:    { type: 'mobilemoneyghana',    network: 'MTN',    currency: 'GHS', country: 'GH', name: 'MTN Ghana',       flag: '🇬🇭' },
  AIRTEL_TZ: { type: 'mobilemoneytanzania', network: 'AIRTEL', currency: 'TZS', country: 'TZ', name: 'Airtel Tanzania', flag: '🇹🇿' },
};
const fwH = () => ({ Authorization: `Bearer ${process.env.FLUTTERWAVE_SECRET_KEY}`, 'Content-Type': 'application/json' });
function fwRedirect(orderId) { return `${process.env.BACKEND_URL||'https://api.redorrange.app'}/api/payments/flutterwave/redirect?order_id=${orderId}`; }

async function fwPaymentLink({ amount, currency, orderId, email, name, phone, options, narration }) {
  const r = await axios.post('https://api.flutterwave.com/v3/payments', {
    tx_ref: orderId, amount: parseFloat(amount), currency: currency.toUpperCase(),
    redirect_url: fwRedirect(orderId),
    payment_options: options||'mobilemoneyrwanda,card,banktransfer',
    customer: { email: email||`${orderId}@pay.redorrange.app`, name: name||'User', phonenumber: phone||'' },
    customizations: { title: 'RedOrrange', description: narration||'Purchase', logo: 'https://redorrange.app/icon.png' },
    meta: { order_id: orderId },
  }, { headers: fwH() });
  if (r.data.status !== 'success') throw new Error(r.data.message||'FW payment link failed');
  return { payment_link: r.data.data.link, tx_ref: orderId };
}

async function fwChargeMM({ amount, currency, orderId, phone, networkCode, email, name }) {
  const cfg = FW_NETWORKS[networkCode]; if (!cfg) throw new Error(`Unknown network: ${networkCode}`);
  const r = await axios.post(`https://api.flutterwave.com/v3/charges?type=${cfg.type}`, {
    tx_ref: orderId, amount: parseFloat(amount), currency: currency||cfg.currency,
    email: email||`${orderId}@pay.redorrange.app`,
    phone_number: phone.replace(/[\s\-()+]/g,''),
    fullname: name||'RedOrrange User', network: cfg.network,
  }, { headers: fwH() });
  if (r.data.status !== 'success') throw new Error(r.data.message||'FW charge failed');
  const mode = r.data.meta?.authorization?.mode;
  return { flw_ref: r.data.data?.flw_ref, tx_ref: orderId, status: r.data.data?.status, message: r.data.message, requires_otp: mode==='otp', requires_pin: mode==='pin', auth_mode: mode, network_config: cfg };
}

async function fwValidateOtp({ flwRef, otp, networkCode }) {
  const cfg = FW_NETWORKS[networkCode] || FW_NETWORKS.MTN_RW;
  const r = await axios.post('https://api.flutterwave.com/v3/validate-charge', { otp, flw_ref: flwRef, type: cfg.type }, { headers: fwH() });
  return { success: r.data.data?.status==='successful', status: r.data.data?.status, tx_ref: r.data.data?.tx_ref, flw_ref: r.data.data?.flw_ref, amount: r.data.data?.amount };
}

async function fwVerifyTx(txId) {
  const r = await axios.get(`https://api.flutterwave.com/v3/transactions/${txId}/verify`, { headers: fwH() });
  const d = r.data.data;
  return { success: d?.status==='successful', status: d?.status, tx_ref: d?.tx_ref, flw_ref: d?.flw_ref, amount: d?.amount, currency: d?.currency, payment_type: d?.payment_type };
}

function fwVerifyWebhookHash(incomingHash) {
  return (process.env.FLUTTERWAVE_SECRET_HASH||process.env.FLUTTERWAVE_SECRET_KEY) === incomingHash;
}

// ── CURRENCY
const RATES = { USD:1, EUR:0.92, GBP:0.79, RWF:1350, KES:132, UGX:3720, TZS:2680, GHS:15.5, NGN:1620, ZMW:26 };
const SYMBOLS = { USD:'$', EUR:'€', GBP:'£', RWF:'RWF ', KES:'KSh ', UGX:'USh ', GHS:'GH₵', NGN:'₦', TZS:'TSh ' };
function toLocal(usd, currency) { return Math.ceil(parseFloat(usd) * (RATES[currency.toUpperCase()]||1)); }
function toUsd(local, currency) { return parseFloat((parseFloat(local)/(RATES[currency.toUpperCase()]||1)).toFixed(4)); }
function sym(c) { return SYMBOLS[c.toUpperCase()]||c; }

// ── FULFILL ORDER (shared by all providers)
async function fulfillOrder(orderId, providerRef, io) {
  const order = await db.queryOne("SELECT * FROM payment_orders WHERE id=? AND status IN ('pending','processing')", [orderId]);
  if (!order) return { success: false, reason: 'not_found_or_already_processed' };
  
  const type = order.target_type || 'coin_package';
  const targetId = order.target_id;

  if (type === 'coin_package') {
    const total = (order.coins||0) + (order.bonus_coins||0);
    const w = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [order.user_id]);
    if (!w) await db.query('INSERT INTO user_wallets (id,user_id,coins) VALUES (?,?,0)', [uuidv4(), order.user_id]);
    const before = w?.coins||0;
    await db.query('UPDATE user_wallets SET coins=coins+? WHERE user_id=?', [total, order.user_id]);
    await db.query('INSERT INTO coin_transactions (id,user_id,type,amount,balance_before,balance_after,reference_id,description) VALUES (?,?,?,?,?,?,?,?)',
      [uuidv4(), order.user_id, 'purchase', total, before, before+total, orderId, `${order.coins} coins${order.bonus_coins>0?' + '+order.bonus_coins+' bonus':''}`]);
    if (io) {
      io.to(`user_${order.user_id}`).emit('coins_credited', { coins_added: total, new_balance: before+total, order_id: orderId });
    }
  } else if (type === 'marketplace_item') {
    // targetId is the escrowId
    await db.query("UPDATE escrow_orders SET status='funded', funded_at=NOW(), payment_ref=? WHERE id=?", [providerRef||null, targetId]);
    await db.query('INSERT INTO escrow_events (order_id, actor_id, event_type, details) VALUES (?,?,?,?)',
      [targetId, order.user_id, 'funded', 'Payment confirmed, escrow funded']);
    
    // Notify seller
    const escrow = await db.queryOne('SELECT e.seller_id, m.title FROM escrow_orders e JOIN marketplace_items m ON e.item_id=m.id WHERE e.id=?', [targetId]);
    if (escrow && io) {
      io.to(`user_${escrow.seller_id}`).emit('notification', { notification: { id: uuidv4(), type: 'escrow_funded', is_read: false, created_at: new Date().toISOString(), message: `Great news! Your item "${escrow.title}" has been paid for. Please ship it to the buyer.` }});
    }
  } else if (type === 'ad_topup') {
    // targetId is the adAccountId
    const account = await db.queryOne('SELECT id,balance_usd FROM ad_accounts WHERE id=?', [targetId]);
    if (account) {
      const before = parseFloat(account.balance_usd);
      const after = before + parseFloat(order.amount_usd);
      await db.query('UPDATE ad_accounts SET balance_usd=?, updated_at=NOW() WHERE id=?', [after, targetId]);
      await db.query('INSERT INTO ad_billing (id, account_id, type, amount, balance_before, balance_after, description, payment_ref) VALUES (?,?,?,?,?,?,?,?)',
        [uuidv4(), targetId, 'topup', order.amount_usd, before, after, "Wallet top-up", providerRef||null]);
      if (io) {
        io.to(`user_${order.user_id}`).emit('ad_balance_updated', { new_balance: after, added: order.amount_usd });
      }
    }
  }

  await db.query("UPDATE payment_orders SET status='completed',provider_ref=?,completed_at=NOW() WHERE id=?", [providerRef||null, orderId]);
  
  if (io) {
    io.to(`user_${order.user_id}`).emit('notification', { notification: { id: uuidv4(), type: 'payment_success', is_read: false, created_at: new Date().toISOString(), message: `Payment of ${order.amount_usd} ${order.currency} confirmed!` }});
    io.to(`user_${order.user_id}`).emit('payment_success', { order_id: orderId, type });
  }
  
  return { success: true, type };
}

module.exports = { stripeCreateIntent, stripeConfirmIntent, stripeVerifyWebhook, stripeCreateSubscription, paypalCreateOrder, paypalCaptureOrder, paypalVerifyWebhook, FW_NETWORKS, fwPaymentLink, fwChargeMM, fwValidateOtp, fwVerifyTx, fwVerifyWebhookHash, toLocal, toUsd, sym, RATES, fulfillOrder };
