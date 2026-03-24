const express    = require('express');
const r          = express.Router();
const { authenticate } = require('../middleware/auth');
const { upload, getFileUrl } = require('../middleware/upload');
const db         = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ════════════════════════════════════════════════════════
// AD ACCOUNTS
// ════════════════════════════════════════════════════════

r.get('/accounts/me', authenticate, async (req, res) => {
  try {
    let account = await db.queryOne('SELECT * FROM ad_accounts WHERE user_id=?', [req.userId]);
    if (!account) return res.json({ success: true, account: null, has_account: false });
    account.verified = !!account.verified;
    const campaigns = await db.queryOne('SELECT COUNT(*) AS total, SUM(CASE WHEN status="active" THEN 1 ELSE 0 END) AS active FROM ad_campaigns WHERE account_id=?', [account.id]);
    res.json({ success: true, account, has_account: true, stats: campaigns });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/accounts', authenticate, async (req, res) => {
  try {
    const { business_name, business_email, website_url, category, country = 'RW', currency = 'USD' } = req.body;
    if (!business_name?.trim()) return res.status(400).json({ success: false, message: 'Business name required' });
    const existing = await db.queryOne('SELECT id FROM ad_accounts WHERE user_id=?', [req.userId]);
    if (existing) return res.json({ success: true, account_id: existing.id, existing: true });
    const id = uuidv4();
    await db.query('INSERT INTO ad_accounts (id, user_id, business_name, business_email, website_url, category, country, currency) VALUES (?,?,?,?,?,?,?,?)',
      [id, req.userId, business_name.trim(), business_email || null, website_url || null, category || null, country, currency]);
    const account = await db.queryOne('SELECT * FROM ad_accounts WHERE id=?', [id]);
    res.status(201).json({ success: true, account });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.put('/accounts/:id', authenticate, async (req, res) => {
  try {
    const { business_name, business_email, website_url, category, billing_address, tax_id } = req.body;
    await db.query('UPDATE ad_accounts SET business_name=COALESCE(?,business_name), business_email=COALESCE(?,business_email), website_url=COALESCE(?,website_url), category=COALESCE(?,category), billing_address=COALESCE(?,billing_address), tax_id=COALESCE(?,tax_id) WHERE id=? AND user_id=?',
      [business_name||null, business_email||null, website_url||null, category||null, billing_address||null, tax_id||null, req.params.id, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── ACCOUNT TOPUP
r.post('/accounts/:id/topup', authenticate, async (req, res) => {
  try {
    const { amount, payment_method = 'card', payment_ref } = req.body;
    if (!amount || amount <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });
    const account = await db.queryOne('SELECT id, balance_usd FROM ad_accounts WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });
    const newBal = parseFloat(account.balance_usd) + parseFloat(amount);
    await db.query('UPDATE ad_accounts SET balance_usd=? WHERE id=?', [newBal, account.id]);
    await db.query('INSERT INTO ad_billing (id, account_id, type, amount, balance_before, balance_after, description, payment_method, payment_ref) VALUES (?,?,?,?,?,?,?,?,?)',
      [uuidv4(), account.id, 'topup', amount, account.balance_usd, newBal, `Ad account top-up $${amount}`, payment_method, payment_ref || null]);
    res.json({ success: true, new_balance: newBal, amount_added: amount });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── BILLING HISTORY
r.get('/accounts/:id/billing', authenticate, async (req, res) => {
  try {
    const txns = await db.query('SELECT * FROM ad_billing WHERE account_id=? ORDER BY created_at DESC LIMIT 50', [req.params.id]);
    res.json({ success: true, transactions: txns });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════
// CAMPAIGNS
// ════════════════════════════════════════════════════════

r.get('/campaigns', authenticate, async (req, res) => {
  try {
    const { status, limit = 20, offset = 0 } = req.query;
    const account = await db.queryOne('SELECT id FROM ad_accounts WHERE user_id=?', [req.userId]);
    if (!account) return res.json({ success: true, campaigns: [] });
    let sql = `
      SELECT c.*,
        (SELECT COUNT(*) FROM ads WHERE campaign_id=c.id) AS ads_count,
        (SELECT SUM(impressions) FROM ad_daily_stats WHERE campaign_id=c.id AND stat_date >= CURRENT_DATE - INTERVAL '7 day') AS impressions_7d,
        (SELECT SUM(clicks) FROM ad_daily_stats WHERE campaign_id=c.id AND stat_date >= CURRENT_DATE - INTERVAL '7 day') AS clicks_7d,
        (SELECT SUM(spend) FROM ad_daily_stats WHERE campaign_id=c.id AND stat_date >= CURRENT_DATE - INTERVAL '7 day') AS spend_7d
      FROM ad_campaigns c WHERE c.account_id=?
    `;
    const params = [account.id];
    if (status) { sql += ' AND c.status=?'; params.push(status); }
    sql += ' ORDER BY c.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    const campaigns = await db.query(sql, params);
    const total = await db.queryOne('SELECT COUNT(*) AS c FROM ad_campaigns WHERE account_id=?' + (status ? ' AND status=?' : ''), status ? [account.id, status] : [account.id]);
    res.json({ success: true, campaigns, total: total?.c || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/campaigns', authenticate, async (req, res) => {
  try {
    const account = await db.queryOne('SELECT id, balance_usd, status FROM ad_accounts WHERE user_id=?', [req.userId]);
    if (!account) return res.status(404).json({ success: false, message: 'No ad account. Create one first.' });
    if (account.status === 'restricted' || account.status === 'disabled') return res.status(403).json({ success: false, message: 'Ad account is restricted' });
    const { name, objective, budget_type = 'daily', budget_amount, start_date, end_date, bid_strategy = 'lowest_cost', target_genders, target_age_min = 13, target_age_max = 65, target_countries, target_cities, target_interests, target_languages, target_devices, target_platforms } = req.body;
    if (!name?.trim()) return res.status(400).json({ success: false, message: 'Campaign name required' });
    if (!objective) return res.status(400).json({ success: false, message: 'Objective required' });
    if (!budget_amount || budget_amount < 1) return res.status(400).json({ success: false, message: 'Budget must be at least $1' });
    if (!start_date) return res.status(400).json({ success: false, message: 'Start date required' });
    const id = uuidv4();
    await db.query(`INSERT INTO ad_campaigns (id, account_id, name, objective, status, budget_type, budget_amount, start_date, end_date, bid_strategy, target_genders, target_age_min, target_age_max, target_countries, target_cities, target_interests, target_languages, target_devices, target_platforms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [id, account.id, name.trim(), objective, 'draft', budget_type, budget_amount, start_date, end_date || null, bid_strategy,
        JSON.stringify(target_genders || ['all']), target_age_min, target_age_max,
        JSON.stringify(target_countries || ['all']), JSON.stringify(target_cities || []),
        JSON.stringify(target_interests || []), JSON.stringify(target_languages || ['all']),
        JSON.stringify(target_devices || ['all']), JSON.stringify(target_platforms || ['all'])
      ]);
    const campaign = await db.queryOne('SELECT * FROM ad_campaigns WHERE id=?', [id]);
    res.status(201).json({ success: true, campaign });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/campaigns/:id', authenticate, async (req, res) => {
  try {
    const campaign = await db.queryOne('SELECT c.*, a.business_name FROM ad_campaigns c JOIN ad_accounts a ON c.account_id=a.id WHERE c.id=? AND a.user_id=?', [req.params.id, req.userId]);
    if (!campaign) return res.status(404).json({ success: false, message: 'Campaign not found' });
    const ads = await db.query('SELECT * FROM ads WHERE campaign_id=? AND status!="archived"', [req.params.id]);
    const daily = await db.query('SELECT * FROM ad_daily_stats WHERE campaign_id=? ORDER BY stat_date DESC LIMIT 30', [req.params.id]);
    res.json({ success: true, campaign, ads, daily_stats: daily });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.put('/campaigns/:id', authenticate, async (req, res) => {
  try {
    const { name, status, budget_amount, end_date, target_age_min, target_age_max, target_countries, target_interests } = req.body;
    const campaign = await db.queryOne('SELECT c.id FROM ad_campaigns c JOIN ad_accounts a ON c.account_id=a.id WHERE c.id=? AND a.user_id=?', [req.params.id, req.userId]);
    if (!campaign) return res.status(404).json({ success: false });
    await db.query('UPDATE ad_campaigns SET name=COALESCE(?,name), status=COALESCE(?,status), budget_amount=COALESCE(?,budget_amount), end_date=COALESCE(?,end_date), target_age_min=COALESCE(?,target_age_min), target_age_max=COALESCE(?,target_age_max), target_countries=COALESCE(?,target_countries), target_interests=COALESCE(?,target_interests) WHERE id=?',
      [name||null, status||null, budget_amount||null, end_date||null, target_age_min||null, target_age_max||null,
        target_countries ? JSON.stringify(target_countries) : null,
        target_interests ? JSON.stringify(target_interests) : null,
        req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/campaigns/:id', authenticate, async (req, res) => {
  try {
    await db.query("UPDATE ad_campaigns c JOIN ad_accounts a ON c.account_id=a.id SET c.status='archived' WHERE c.id=? AND a.user_id=?", [req.params.id, req.userId]);
    await db.query("UPDATE ads SET status='archived' WHERE campaign_id=?", [req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Campaign analytics
r.get('/campaigns/:id/analytics', authenticate, async (req, res) => {
  try {
    const { period = '7d' } = req.query;
    const days = period === '30d' ? 30 : period === '90d' ? 90 : 7;
    const [daily, totals, topAds, hourly] = await Promise.all([
      db.query("SELECT * FROM ad_daily_stats WHERE campaign_id=? AND stat_date >= CURRENT_DATE - (? * INTERVAL '1 day') ORDER BY stat_date", [req.params.id, days]),
      db.queryOne("SELECT SUM(impressions) AS impressions, SUM(clicks) AS clicks, SUM(spend) AS spend, SUM(reach) AS reach, SUM(conversions) AS conversions, SUM(video_views) AS video_views FROM ad_daily_stats WHERE campaign_id=? AND stat_date >= CURRENT_DATE - (? * INTERVAL '1 day')", [req.params.id, days]),
      db.query("SELECT a.id, a.name, a.format, SUM(s.impressions) AS impressions, SUM(s.clicks) AS clicks, SUM(s.spend) AS spend FROM ad_daily_stats s JOIN ads a ON s.ad_id=a.id WHERE s.campaign_id=? AND s.stat_date >= CURRENT_DATE - (? * INTERVAL '1 day') GROUP BY a.id ORDER BY clicks DESC LIMIT 5", [req.params.id, days]),
      db.query("SELECT EXTRACT(HOUR FROM created_at) AS hour, COUNT(*) AS clicks FROM ad_clicks WHERE campaign_id=? AND created_at >= NOW() - (? * INTERVAL '1 day') GROUP BY hour ORDER BY hour", [req.params.id, days]),
    ]);
    const ctr  = totals?.impressions > 0 ? (totals.clicks / totals.impressions * 100).toFixed(2) : '0.00';
    const cpm  = totals?.impressions > 0 ? (totals.spend / totals.impressions * 1000).toFixed(2) : '0.00';
    const cpc  = totals?.clicks > 0 ? (totals.spend / totals.clicks).toFixed(2) : '0.00';
    res.json({ success: true, daily, totals: { ...totals, ctr, cpm, cpc }, top_ads: topAds, hourly_clicks: hourly });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════
// ADS (CREATIVES)
// ════════════════════════════════════════════════════════

r.get('/campaigns/:campaignId/ads', authenticate, async (req, res) => {
  try {
    const ads = await db.query(`SELECT a.*, s.impressions_7d, s.clicks_7d, s.spend_7d FROM ads a LEFT JOIN (SELECT ad_id, SUM(impressions) AS impressions_7d, SUM(clicks) AS clicks_7d, SUM(spend) AS spend_7d FROM ad_daily_stats WHERE stat_date >= CURRENT_DATE - INTERVAL '7 day' GROUP BY ad_id) s ON a.id=s.ad_id WHERE a.campaign_id=? ORDER BY a.created_at DESC`, [req.params.campaignId]);
    res.json({ success: true, ads });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/campaigns/:campaignId/ads', authenticate, upload.single('media'), async (req, res) => {
  try {
    const { name, format, headline, primary_text, description, cta_text = 'Learn More', cta_url, display_url, carousel_items, story_bg_color, story_text_overlay } = req.body;
    if (!name?.trim() || !format) return res.status(400).json({ success: false, message: 'name and format required' });
    if (!cta_url?.trim()) return res.status(400).json({ success: false, message: 'Destination URL required' });
    const campaign = await db.queryOne('SELECT c.id, c.account_id FROM ad_campaigns c JOIN ad_accounts a ON c.account_id=a.id WHERE c.id=? AND a.user_id=?', [req.params.campaignId, req.userId]);
    if (!campaign) return res.status(404).json({ success: false });
    let mediaUrl = null, mediaDuration = null, mediaWidth = null, mediaHeight = null, mediaSize = null;
    if (req.file) { mediaUrl = getFileUrl(req, req.file.path); mediaSize = req.file.size; }
    const id = uuidv4();
    await db.query(`INSERT INTO ads (id, ad_set_id, campaign_id, account_id, name, format, status, headline, primary_text, description, cta_text, cta_url, display_url, media_url, media_duration, media_width, media_height, media_size, carousel_items, story_bg_color, story_text_overlay) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [id, 'default', req.params.campaignId, campaign.account_id, name.trim(), format, 'pending_review', headline||null, primary_text||null, description||null, cta_text, cta_url.trim(), display_url||null, mediaUrl, mediaDuration, mediaWidth, mediaHeight, mediaSize,
        carousel_items ? JSON.stringify(typeof carousel_items === 'string' ? JSON.parse(carousel_items) : carousel_items) : null,
        story_bg_color||null, story_text_overlay||null
      ]);
    const ad = await db.queryOne('SELECT * FROM ads WHERE id=?', [id]);
    res.status(201).json({ success: true, ad, message: 'Ad submitted for review. Usually approved within 24 hours.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.put('/ads/:id', authenticate, async (req, res) => {
  try {
    const { name, headline, primary_text, description, cta_text, cta_url, status } = req.body;
    const ad = await db.queryOne('SELECT a.id FROM ads a JOIN ad_accounts ac ON a.account_id=ac.id WHERE a.id=? AND ac.user_id=?', [req.params.id, req.userId]);
    if (!ad) return res.status(404).json({ success: false });
    if (status && ['active','paused'].includes(status)) await db.query('UPDATE ads SET status=? WHERE id=?', [status, req.params.id]);
    else await db.query('UPDATE ads SET name=COALESCE(?,name), headline=COALESCE(?,headline), primary_text=COALESCE(?,primary_text), description=COALESCE(?,description), cta_text=COALESCE(?,cta_text), cta_url=COALESCE(?,cta_url), status="pending_review" WHERE id=?',
      [name||null, headline||null, primary_text||null, description||null, cta_text||null, cta_url||null, req.params.id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/ads/:id', authenticate, async (req, res) => {
  try {
    await db.query("UPDATE ads a JOIN ad_accounts ac ON a.account_id=ac.id SET a.status='archived' WHERE a.id=? AND ac.user_id=?", [req.params.id, req.userId]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Single ad analytics
r.get('/ads/:id/analytics', authenticate, async (req, res) => {
  try {
    const daily = await db.query('SELECT * FROM ad_daily_stats WHERE ad_id=? ORDER BY stat_date DESC LIMIT 30', [req.params.id]);
    const totals = await db.queryOne('SELECT SUM(impressions) AS impressions, SUM(clicks) AS clicks, SUM(spend) AS spend, SUM(reach) AS reach, SUM(conversions) AS conversions FROM ad_daily_stats WHERE ad_id=?', [req.params.id]);
    const ad = await db.queryOne('SELECT video_views,video_pct_25,video_pct_50,video_pct_75,video_pct_100,saves,shares,reactions,comments_count FROM ads WHERE id=?', [req.params.id]);
    const ctr = totals?.impressions > 0 ? (totals.clicks / totals.impressions * 100).toFixed(2) : '0.00';
    const cpm = totals?.impressions > 0 ? (totals.spend / totals.impressions * 1000).toFixed(2) : '0.00';
    res.json({ success: true, daily, totals: {...totals, ctr, cpm}, creative_stats: ad });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════
// AD DELIVERY (called by feed/stories/reels to get ads)
// ════════════════════════════════════════════════════════

r.get('/serve/:placement', async (req, res) => {
  try {
    const uid      = req.query.user_id;
    const placement = req.params.placement; // feed, story, reel, explore
    const platform  = req.query.platform || 'android';
    const country   = req.query.country  || 'RW';
    const device    = req.query.device   || 'mobile';

    // Build ad query with targeting
    let sql = `
      SELECT a.*, c.objective, c.target_age_min, c.target_age_max, c.target_countries,
        c.target_genders, c.target_interests, c.budget_amount, c.spent_amount,
        ac.business_name
      FROM ads a
      JOIN ad_campaigns c ON a.campaign_id=c.id
      JOIN ad_accounts ac ON a.account_id=ac.id
      WHERE a.status='active'
        AND c.status='active'
        AND ac.status='active'
        AND c.start_date <= CURRENT_DATE
        AND (c.end_date IS NULL OR c.end_date >= CURRENT_DATE)
        AND c.spent_amount < c.budget_amount
    `;
    const params = [];

    // Exclude hidden ads for this user
    if (uid) { sql += ' AND a.id NOT IN (SELECT ad_id FROM hidden_ads WHERE user_id=?)'; params.push(uid); }

    sql += ' ORDER BY RAND() LIMIT 3'; // Simplified delivery (production would use ML auction)

    const candidates = await db.query(sql, params);
    if (!candidates.length) return res.json({ success: true, ad: null });

    const ad = candidates[0];

    // Record impression asynchronously
    if (uid || true) {
      const cost = 0.002; // $0.002 CPM equivalent per impression
      db.query('INSERT INTO ad_impressions (ad_id, campaign_id, user_id, placement, device_type, platform, country, cost) VALUES (?,?,?,?,?,?,?,?)',
        [ad.id, ad.campaign_id, uid||null, placement, device, platform, country, cost]).catch(()=>{});
      db.query('UPDATE ads SET impressions=impressions+1 WHERE id=?', [ad.id]).catch(()=>{});
      db.query('UPDATE ad_campaigns SET impressions_total=impressions_total+1, spent_amount=spent_amount+? WHERE id=?', [cost, ad.campaign_id]).catch(()=>{});
      db.query('UPDATE ad_accounts SET total_spent=total_spent+? WHERE id=?', [cost, ad.account_id]).catch(()=>{});
      // Upsert daily stats
      db.query(`INSERT INTO ad_daily_stats (id, ad_id, campaign_id, account_id, stat_date, impressions, spend) VALUES (gen_random_uuid(),?,?,?,CURRENT_DATE,1,?) ON CONFLICT (ad_id, stat_date) DO UPDATE SET impressions=ad_daily_stats.impressions+1, spend=ad_daily_stats.spend+EXCLUDED.spend`,
        [ad.id, ad.campaign_id, ad.account_id, cost, cost]).catch(()=>{});
    }

    res.json({ success: true, ad: { id: ad.id, campaign_id: ad.campaign_id, format: ad.format, headline: ad.headline, primary_text: ad.primary_text, description: ad.description, cta_text: ad.cta_text, cta_url: ad.cta_url, display_url: ad.display_url, media_url: ad.media_url, media_thumb_url: ad.media_thumb_url, carousel_items: ad.carousel_items, story_bg_color: ad.story_bg_color, story_text_overlay: ad.story_text_overlay, business_name: ad.business_name, objective: ad.objective } });
  } catch (e) { res.status(500).json({ success: true, ad: null }); }
});

// ── Record click
r.post('/click/:adId', async (req, res) => {
  try {
    const { user_id, placement, click_type = 'cta' } = req.body;
    const ad = await db.queryOne('SELECT campaign_id, account_id FROM ads WHERE id=?', [req.params.adId]);
    if (!ad) return res.json({ success: false });
    const cost = 0.05; // $0.05 CPC
    db.query('INSERT INTO ad_clicks (ad_id, campaign_id, user_id, placement, click_type, cost, ip_address, user_agent) VALUES (?,?,?,?,?,?,?,?)',
      [req.params.adId, ad.campaign_id, user_id||null, placement||null, click_type, cost, req.ip, req.headers['user-agent']?.substring(0,500)||null]).catch(()=>{});
    db.query('UPDATE ads SET clicks=clicks+1, cost_per_click=(spend+?)/(clicks+1) WHERE id=?', [cost, req.params.adId]).catch(()=>{});
    db.query('UPDATE ad_campaigns SET clicks_total=clicks_total+1, spent_amount=spent_amount+? WHERE id=?', [cost, ad.campaign_id]).catch(()=>{});
    db.query(`INSERT INTO ad_daily_stats (id, ad_id, campaign_id, account_id, stat_date, clicks, spend) VALUES (gen_random_uuid(),?,?,?,CURRENT_DATE,1,?) ON CONFLICT (ad_id, stat_date) DO UPDATE SET clicks=ad_daily_stats.clicks+1, spend=ad_daily_stats.spend+EXCLUDED.spend`,
      [req.params.adId, ad.campaign_id, ad.account_id, cost, cost]).catch(()=>{});
    res.json({ success: true });
  } catch (e) { res.json({ success: false }); }
});

// ── Hide ad (user action)
r.post('/hide/:adId', async (req, res) => {
  try {
    const { user_id, reason = 'not_relevant' } = req.body;
    if (!user_id) return res.json({ success: false });
    await db.query('INSERT INTO hidden_ads (ad_id, user_id, reason) VALUES (?,?,?)', [req.params.adId, user_id, reason]);
    res.json({ success: true });
  } catch (e) { res.json({ success: false }); }
});

// ── Report ad
r.post('/report/:adId', async (req, res) => {
  try {
    const { user_id, reason, details } = req.body;
    if (!user_id || !reason) return res.status(400).json({ success: false });
    await db.query('INSERT INTO ad_reports (id, ad_id, user_id, reason, details) VALUES (?,?,?,?,?)', [uuidv4(), req.params.adId, user_id, reason, details||null]);
    res.json({ success: true, message: 'Report submitted. Thank you for keeping RedOrrange safe.' });
  } catch (e) { res.json({ success: false }); }
});

// ── Save/unsave ad
r.post('/save/:adId', async (req, res) => {
  try {
    const { user_id } = req.body;
    if (!user_id) return res.json({ success: false });
    const ex = await db.queryOne('SELECT ad_id FROM saved_ads WHERE ad_id=? AND user_id=?', [req.params.id, user_id]);
    if (ex) { await db.query('DELETE FROM saved_ads WHERE ad_id=? AND user_id=?', [req.params.id, user_id]); return res.json({ success: true, saved: false }); }
    await db.query('INSERT INTO saved_ads (ad_id, user_id) VALUES (?,?)', [req.params.id, user_id]);
    res.json({ success: true, saved: true });
  } catch (e) { res.json({ success: false }); }
});

// ── Like/unlike ad
r.post('/:id/like', authenticate, async (req, res) => {
  try {
    const uid = req.userId; const adId = req.params.id;
    const ex = await db.queryOne('SELECT id FROM likes WHERE target_type="ad" AND target_id=? AND user_id=?', [adId, uid]);
    if (ex) {
      await db.query('DELETE FROM likes WHERE id=?', [ex.id]);
      await db.query('UPDATE ads SET reactions=GREATEST(0,reactions-1) WHERE id=?', [adId]);
      return res.json({ success: true, liked: false });
    }
    await db.query('INSERT INTO likes (user_id, target_type, target_id) VALUES (?,?,?)', [uid, 'ad', adId]);
    await db.query('UPDATE ads SET reactions=reactions+1 WHERE id=?', [adId]);
    const count = await db.queryOne('SELECT reactions FROM ads WHERE id=?', [adId]);
    res.json({ success: true, liked: true, likes_count: count?.reactions || 0 });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── GET ad comments
r.get('/:id/comments', async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const offset = (page - 1) * parseInt(limit);
    const comments = await db.query(`
      SELECT c.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) FROM likes WHERE target_type='comment' AND target_id=c.id) AS likes_count
      FROM comments c JOIN users u ON c.user_id=u.id
      WHERE c.target_type='ad' AND c.target_id=? AND c.is_deleted=FALSE
      ORDER BY c.created_at DESC LIMIT ? OFFSET ?
    `, [req.params.id, parseInt(limit), parseInt(offset)]);
    res.json({ success: true, comments });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── POST ad comment
r.post('/:id/comments', authenticate, async (req, res) => {
  try {
    const { content } = req.body;
    if (!content?.trim()) return res.status(400).json({ success: false, message: 'Content required' });
    const id = uuidv4();
    await db.query('INSERT INTO comments (id, user_id, target_type, target_id, content) VALUES (?,?,?,?,?)',
      [id, req.userId, 'ad', req.params.id, content.trim()]);
    await db.query('UPDATE ads SET comments_count=comments_count+1 WHERE id=?', [req.params.id]);
    const comment = await db.queryOne('SELECT c.*, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id=u.id WHERE c.id=?', [id]);
    res.status(201).json({ success: true, comment });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════
// AUDIENCE INSIGHTS & INTERESTS
// ════════════════════════════════════════════════════════

r.get('/interests', authenticate, async (req, res) => {
  const interests = [
    { id: 'technology', name: 'Technology', icon: 'computer', size: 45000 },
    { id: 'fashion', name: 'Fashion & Style', icon: 'style', size: 38000 },
    { id: 'food', name: 'Food & Cooking', icon: 'restaurant', size: 52000 },
    { id: 'fitness', name: 'Fitness & Health', icon: 'fitness_center', size: 29000 },
    { id: 'travel', name: 'Travel', icon: 'flight', size: 41000 },
    { id: 'music', name: 'Music', icon: 'music_note', size: 67000 },
    { id: 'sports', name: 'Sports', icon: 'sports_soccer', size: 58000 },
    { id: 'gaming', name: 'Gaming', icon: 'games', size: 34000 },
    { id: 'business', name: 'Business', icon: 'business', size: 22000 },
    { id: 'education', name: 'Education', icon: 'school', size: 31000 },
    { id: 'beauty', name: 'Beauty', icon: 'face', size: 27000 },
    { id: 'finance', name: 'Finance', icon: 'account_balance', size: 18000 },
    { id: 'art', name: 'Art & Design', icon: 'palette', size: 24000 },
    { id: 'parenting', name: 'Parenting', icon: 'child_care', size: 19000 },
    { id: 'news', name: 'News & Politics', icon: 'article', size: 43000 },
    { id: 'movies', name: 'Movies & TV', icon: 'movie', size: 55000 },
    { id: 'animals', name: 'Pets & Animals', icon: 'pets', size: 32000 },
    { id: 'automotive', name: 'Automotive', icon: 'directions_car', size: 21000 },
    { id: 'real_estate', name: 'Real Estate', icon: 'home', size: 16000 },
    { id: 'startups', name: 'Startups', icon: 'rocket_launch', size: 14000 },
  ];
  res.json({ success: true, interests });
});

// ── Audience size estimate for targeting
r.post('/audience-estimate', authenticate, async (req, res) => {
  try {
    const { target_countries = ['all'], target_age_min = 13, target_age_max = 65, target_genders = ['all'], target_interests = [] } = req.body;
    // Real estimate query
    let sql = "SELECT COUNT(*) AS c FROM users WHERE username IS NOT NULL AND created_at > '2020-01-01'";
    const params = [];
    if (!target_countries.includes('all') && target_countries.length > 0) {
      sql += ' AND location LIKE ?'; params.push(`%${target_countries[0]}%`);
    }
    const raw = await db.queryOne(sql, params);
    const base = raw?.c || 1000;
    // Simulate targeting narrowing
    const genderMult  = target_genders.includes('all') ? 1 : 0.5;
    const ageMult     = Math.min(1, (target_age_max - target_age_min) / 52);
    const interestMult = target_interests.length === 0 ? 1 : Math.max(0.1, 1 - target_interests.length * 0.06);
    const estimate    = Math.max(1000, Math.round(base * genderMult * ageMult * interestMult));
    const potential   = Math.round(estimate * 1.3);
    res.json({ success: true, audience_size: estimate, potential_reach: potential, accuracy: 'estimated' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ════════════════════════════════════════════════════════
// OVERVIEW DASHBOARD
// ════════════════════════════════════════════════════════

r.get('/dashboard', authenticate, async (req, res) => {
  try {
    const account = await db.queryOne('SELECT * FROM ad_accounts WHERE user_id=?', [req.userId]);
    if (!account) return res.json({ success: true, has_account: false });
    const [campaigns, statsToday, statsWeek, topCampaigns, recentBilling] = await Promise.all([
      db.queryOne("SELECT COUNT(*) AS total, SUM(CASE WHEN status='active' THEN 1 ELSE 0 END) AS active, SUM(CASE WHEN status='paused' THEN 1 ELSE 0 END) AS paused, SUM(CASE WHEN status='draft' THEN 1 ELSE 0 END) AS draft FROM ad_campaigns WHERE account_id=?", [account.id]),
      db.queryOne("SELECT COALESCE(SUM(impressions),0) AS impressions, COALESCE(SUM(clicks),0) AS clicks, COALESCE(SUM(spend),0) AS spend, COALESCE(SUM(conversions),0) AS conversions FROM ad_daily_stats WHERE account_id=? AND stat_date=CURRENT_DATE", [account.id]),
      db.queryOne("SELECT COALESCE(SUM(impressions),0) AS impressions, COALESCE(SUM(clicks),0) AS clicks, COALESCE(SUM(spend),0) AS spend FROM ad_daily_stats WHERE account_id=? AND stat_date >= CURRENT_DATE - INTERVAL '7 day'", [account.id]),
      db.query("SELECT c.id, c.name, c.objective, c.status, SUM(s.impressions) AS impressions, SUM(s.clicks) AS clicks, SUM(s.spend) AS spend FROM ad_campaigns c JOIN ad_daily_stats s ON c.id=s.campaign_id WHERE c.account_id=? AND s.stat_date >= CURRENT_DATE - INTERVAL '7 day' GROUP BY c.id ORDER BY spend DESC LIMIT 5", [account.id]),
      db.query('SELECT * FROM ad_billing WHERE account_id=? ORDER BY created_at DESC LIMIT 5', [account.id]),
    ]);
    res.json({ success: true, account, campaigns, stats_today: statsToday, stats_week: statsWeek, top_campaigns: topCampaigns, recent_billing: recentBilling });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Templates
r.get('/templates', authenticate, async (req, res) => {
  try {
    const templates = await db.query('SELECT * FROM ad_templates WHERE is_active=1 ORDER BY created_at');
    res.json({ success: true, templates });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;

// ══════════════════════════════════════════════════════
// AUTOMATED: Expire ended campaigns (call via cron)
// ══════════════════════════════════════════════════════
r.post('/cron/expire-campaigns', async (req, res) => {
  try {
    const result = await db.query(`
      UPDATE ad_campaigns
      SET status='completed'
      WHERE status='active'
        AND end_date IS NOT NULL
        AND end_date < CURRENT_DATE
    `);
    // Also pause campaigns that exceeded budget
    await db.query(`
      UPDATE ad_campaigns
      SET status='paused'
      WHERE status='active'
        AND spent_amount >= budget_amount
    `);
    res.json({ success: true, expired: result.affectedRows });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});
