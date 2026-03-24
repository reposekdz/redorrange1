'use strict';
/**
 * Advanced features: analytics, AI suggestions, collections, smart content,
 * user insights, trending, content moderation signals
 */
const express = require('express');
const r       = express.Router();
const { authenticate } = require('../middleware/auth');
const db      = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const rec     = require('../services/recommendationEngine');

// ── PROFILE ANALYTICS
r.get('/analytics/profile', authenticate, async (req, res) => {
  try {
    const uid    = req.userId;
    const period = req.query.period || '30d';
    const days   = period === '90d' ? 90 : period === '7d' ? 7 : 30;

    const [views, posts, engagement, followers, reachData, topPosts] = await Promise.all([
      db.queryOne(`
        SELECT COUNT(*) AS c FROM post_views pv JOIN posts p ON pv.post_id=p.id
        WHERE p.user_id=? AND pv.viewed_at > DATE_SUB(NOW(), INTERVAL '? day')
      `, [uid, days]),
      db.queryOne(`SELECT COUNT(*) AS c, COALESCE(SUM(likes_count),0) AS likes, COALESCE(SUM(comments_count),0) AS comments, COALESCE(SUM(views_count),0) AS views FROM posts WHERE user_id=? AND is_deleted=FALSE AND created_at > DATE_SUB(NOW(), INTERVAL '? day')`, [uid, days]),
      db.queryOne(`SELECT followers_count, following_count FROM users WHERE id=?`, [uid]),
      db.query(`
        SELECT DATE(created_at) AS d, COUNT(*) AS new_followers
        FROM follows WHERE following_id=? AND status='accepted' AND created_at > DATE_SUB(NOW(), INTERVAL '? day')
        GROUP BY DATE(created_at) ORDER BY d
      `, [uid, days]),
      db.queryOne(`
        SELECT COALESCE(SUM(p.views_count),0) AS total_reach FROM posts p WHERE p.user_id=? AND p.is_deleted=FALSE
      `, [uid]),
      db.query(`
        SELECT id, caption, likes_count, comments_count, views_count, created_at,
          (SELECT media_url FROM post_media WHERE post_id=p.id LIMIT 1) AS thumbnail
        FROM posts p WHERE user_id=? AND is_deleted=FALSE
        ORDER BY likes_count DESC LIMIT 5
      `, [uid]),
    ]);

    const engagementRate = await rec.getUserEngagementRate(uid, days);
    const totalPosts = posts?.c || 0;
    const totalLikes = posts?.likes || 0;
    const totalViews = posts?.views || 0;

    res.json({
      success: true,
      profile_views:   views?.c || 0,
      total_posts:     totalPosts,
      total_likes:     totalLikes,
      total_comments:  posts?.comments || 0,
      impressions:     reachData?.total_reach || 0,
      followers_count: engagement?.followers_count || 0,
      following_count: engagement?.following_count || 0,
      engagement_rate: engagementRate.toFixed(1),
      daily_followers: followers,
      top_posts:       topPosts,
      period:          period,
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── POST INSIGHTS
r.get('/analytics/post/:id', authenticate, async (req, res) => {
  try {
    const pid = req.params.id;
    const post = await db.queryOne('SELECT * FROM posts WHERE id=? AND user_id=?', [pid, req.userId]);
    if (!post) return res.status(404).json({ success: false, message: 'Not found or not your post' });

    const [views, likes, comments, saves, shares, reactions, hourly] = await Promise.all([
      db.queryOne(`SELECT COUNT(*) AS c FROM post_views WHERE post_id=?`, [pid]),
      db.queryOne(`SELECT COUNT(*) AS c FROM likes WHERE target_type='post' AND target_id=?`, [pid]),
      db.queryOne(`SELECT COUNT(*) AS c FROM comments WHERE target_type='post' AND target_id=? AND is_deleted=FALSE`, [pid]),
      db.queryOne(`SELECT COUNT(*) AS c FROM saved_posts WHERE post_id=?`, [pid]),
      db.queryOne(`SELECT COUNT(*) AS c FROM shares WHERE post_id=?`, [pid]),
      db.query(`SELECT reaction_type, COUNT(*) AS cnt FROM likes WHERE target_type='post' AND target_id=? GROUP BY reaction_type`, [pid]),
      db.query(`
        SELECT HOUR(pv.viewed_at) AS hour, COUNT(*) AS views
        FROM post_views pv WHERE pv.post_id=? GROUP BY HOUR(pv.viewed_at) ORDER BY hour
      `, [pid]),
    ]);

    const viewCount = views?.c || post.views_count || 0;
    const likeCount = likes?.c || post.likes_count || 0;
    const commentCount = comments?.c || post.comments_count || 0;
    const saveCount  = saves?.c  || 0;
    const shareCount = shares?.c || post.shares_count || 0;

    res.json({
      success: true,
      views_count:     viewCount,
      reach:           Math.round(viewCount * 1.15),
      impressions:     Math.round(viewCount * 1.4),
      likes_count:     likeCount,
      comments_count:  commentCount,
      shares_count:    shareCount,
      saves_count:     saveCount,
      engagement_rate: viewCount > 0 ? ((likeCount + commentCount) / viewCount * 100).toFixed(2) : '0.00',
      followers_pct:   0,
      reactions_breakdown: reactions,
      hourly_views:    hourly,
      virality_score:  rec.predictVirality(post),
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── SMART REPLIES for messages
r.get('/messages/:id/smart-replies', authenticate, async (req, res) => {
  try {
    const msg = await db.queryOne('SELECT content, type FROM messages WHERE id=?', [req.params.id]);
    const text = (msg?.content || '').toLowerCase().trim();

    let suggestions = [];
    if (!text || text.length < 2) {
      suggestions = ['👍', 'Got it!', 'Thanks!'];
    } else if (/how are you|how r u|how's it going|wassup|sup/.test(text)) {
      suggestions = ["I'm great! 😊", 'Pretty good, you?', 'Doing well, thanks!'];
    } else if (/thank|thanks|thx|ty/.test(text)) {
      suggestions = ['You\'re welcome! 😊', 'Anytime! 🙌', 'No problem!'];
    } else if (/hello|hi |hey|good morning|good evening/.test(text)) {
      suggestions = ['Hey! 👋', 'Hello there!', 'Hi! How are you?'];
    } else if (/where|when|what time|location/.test(text)) {
      suggestions = ['Let me check', 'Good question!', 'I\'ll find out'];
    } else if (/ok|okay|sure|alright|sounds good/.test(text)) {
      suggestions = ['Perfect! ✅', 'Sounds good!', 'Great!'];
    } else if (/yes|yeah|yep|yup/.test(text)) {
      suggestions = ['Yes! 🙌', 'Absolutely!', 'Of course!'];
    } else if (/no |nope|not really/.test(text)) {
      suggestions = ['I see 🤔', 'Maybe later?', 'That\'s fine!'];
    } else if (/love|miss|❤|heart/.test(text)) {
      suggestions = ['❤️', 'Miss you too!', '💕'];
    } else if (/dinner|lunch|breakfast|eat|food|hungry/.test(text)) {
      suggestions = ['Sounds delicious! 😋', 'Let\'s eat!', 'Yum!'];
    } else if (/\?$/.test(text)) {
      suggestions = ['Yes 👍', 'Not sure yet', 'Let me think...'];
    } else if (/lol|haha|funny|😂|😆/.test(text)) {
      suggestions = ['😂', 'Haha so true!', 'Can\'t stop laughing!'];
    } else {
      suggestions = ['👍', 'OK!', 'Got it'];
    }

    res.json({ success: true, suggestions });
  } catch (e) { res.json({ success: true, suggestions: ['👍', 'OK!', 'Thanks'] }); }
});

// ── COLLECTIONS (save posts to named collections)
r.get('/collections', authenticate, async (req, res) => {
  try {
    const cols = await db.query(`
      SELECT c.*, COUNT(ci.id) AS items_count,
        (SELECT post_id FROM collection_items WHERE collection_id=c.id ORDER BY created_at DESC LIMIT 1) AS latest_post_id,
        (SELECT pm.media_url FROM post_media pm JOIN collection_items ci2 ON pm.post_id=ci2.post_id WHERE ci2.collection_id=c.id ORDER BY ci2.created_at DESC LIMIT 1) AS cover_thumb
      FROM collections c
      LEFT JOIN collection_items ci ON c.id=ci.collection_id
      WHERE c.user_id=?
      GROUP BY c.id ORDER BY c.created_at DESC
    `, [req.userId]);
    res.json({ success: true, collections: cols });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/collections', authenticate, async (req, res) => {
  try {
    const { name, description, is_private = false } = req.body;
    if (!name?.trim()) return res.status(400).json({ success: false, message: 'Name required' });
    const id = uuidv4();
    await db.query('INSERT INTO collections (id, user_id, name, description, is_private) VALUES (?,?,?,?,?)', [id, req.userId, name.trim(), description || null, is_private ? 1 : 0]);
    res.status(201).json({ success: true, collection: { id, name, description, is_private } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/collections/:id/add', authenticate, async (req, res) => {
  try {
    const { post_id } = req.body;
    await db.query('INSERT INTO collection_items (collection_id, post_id) VALUES (?,?)', [req.params.id, post_id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/collections/:id/items/:postId', authenticate, async (req, res) => {
  await db.query('DELETE FROM collection_items WHERE collection_id=? AND post_id=?', [req.params.id, req.params.postId]);
  res.json({ success: true });
});

// ── AI CONTENT SUGGESTIONS (topic ideas for creators)
r.get('/suggestions/content', authenticate, async (req, res) => {
  try {
    const uid = req.userId;
    // Get user's top performing hashtags
    const topTags = await db.query(`
      SELECT h.name, COUNT(*) AS uses, MAX(p.likes_count) AS best_likes
      FROM post_hashtags ph
      JOIN hashtags h ON ph.hashtag_id=h.id
      JOIN posts p ON ph.post_id=p.id
      WHERE p.user_id=? AND p.is_deleted=FALSE
      GROUP BY h.id ORDER BY best_likes DESC LIMIT 5
    `, [uid]);

    const trending = await rec.getTrendingHashtags(10);
    const engRate  = await rec.getUserEngagementRate(uid, 30);

    const suggestions = [
      { type: 'timing', title: 'Best time to post', desc: 'Your audience is most active 6-8 PM on weekdays', icon: 'schedule' },
      { type: 'format', title: 'Try Reels', desc: 'Reels get 3x more reach than regular posts right now', icon: 'movie_creation' },
      { type: 'hashtag', title: 'Trending hashtags', desc: 'These are trending today — add them to your next post', hashtags: trending.slice(0,5).map(t => t.name), icon: 'tag' },
      { type: 'engagement', title: 'Boost engagement', desc: engRate < 3 ? 'Ask a question in your next caption to get more comments' : 'Keep it up! Your engagement is above average', icon: 'trending_up' },
      { type: 'consistency', title: 'Post consistently', desc: 'Post 1-2x per day for best algorithm reach', icon: 'calendar_today' },
      { type: 'collab', title: 'Collaborate', desc: 'Tag other creators in your posts to reach new audiences', icon: 'people' },
    ];

    if (topTags.length > 0) {
      suggestions.push({ type: 'your_tags', title: 'Your winning hashtags', desc: 'These hashtags performed best for you', hashtags: topTags.map(t => t.name), icon: 'stars' });
    }

    res.json({ success: true, suggestions, engagement_rate: engRate });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── LINK PREVIEW (for chat messages with URLs)
r.post('/link-preview', authenticate, async (req, res) => {
  try {
    const { url } = req.body;
    if (!url) return res.json({ success: false });
    // Check cache
    const cached = await db.queryOne("SELECT * FROM link_previews WHERE url=? AND created_at > NOW() - INTERVAL '24 hours'", [url]);
    if (cached) return res.json({ success: true, preview: cached });

    // Fetch metadata (simple approach)
    const axios = require('axios');
    const resp  = await axios.get(url, { timeout: 5000, headers: { 'User-Agent': 'RedOrrangeBot/1.0' } });
    const html  = resp.data?.toString() || '';
    const titleM = html.match(/<meta property="og:title" content="([^"]+)"/i) || html.match(/<title>([^<]+)<\/title>/i);
    const descM  = html.match(/<meta property="og:description" content="([^"]+)"/i) || html.match(/<meta name="description" content="([^"]+)"/i);
    const imgM   = html.match(/<meta property="og:image" content="([^"]+)"/i);
    const siteM  = html.match(/<meta property="og:site_name" content="([^"]+)"/i);

    const preview = { url, title: titleM?.[1] || '', description: descM?.[1] || '', image: imgM?.[1] || null, site_name: siteM?.[1] || new URL(url).hostname };
    await db.query(
      'INSERT INTO link_previews (url, title, description, image_url, site_name) VALUES (?,?,?,?,?) ON CONFLICT (url) DO UPDATE SET title=EXCLUDED.title, description=EXCLUDED.description, image_url=EXCLUDED.image_url, site_name=EXCLUDED.site_name',
      [preview.url, preview.title, preview.description, preview.image, preview.site_name]).catch(()=>{});
    res.json({ success: true, preview });
  } catch (e) { res.json({ success: false, preview: null }); }
});

// ── USER STATUS / MOOD
r.post('/users/status', authenticate, async (req, res) => {
  try {
    const { status_text, mood, expires_in_hours = 24 } = req.body;
    const expiresAt = new Date(Date.now() + expires_in_hours * 3600000);
    await db.query('UPDATE users SET status_text=? WHERE id=?', [status_text || null, req.userId]);
    if (mood) {
      await db.query(
        'INSERT INTO user_moods (user_id, mood, text, expires_at) VALUES (?,?,?,?) ON CONFLICT (user_id) DO UPDATE SET mood=?, text=?, expires_at=?',
        [req.userId, mood, status_text || null, expiresAt, mood, status_text || null, expiresAt]);
    }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── POST BOOST
r.post('/posts/:id/boost', authenticate, async (req, res) => {
  try {
    const { budget, duration_days = 3, goal = 'reach' } = req.body;
    const post = await db.queryOne('SELECT id FROM posts WHERE id=? AND user_id=?', [req.params.id, req.userId]);
    if (!post) return res.status(404).json({ success: false, message: 'Post not found' });
    const coins = Math.round(budget * 100);
    const wallet = await db.queryOne('SELECT coins FROM user_wallets WHERE user_id=?', [req.userId]);
    if (!wallet || wallet.coins < coins) return res.status(400).json({ success: false, message: 'Insufficient coins' });
    const boostId = uuidv4();
    await db.query('UPDATE user_wallets SET coins=coins-? WHERE user_id=?', [coins, req.userId]);
    await db.query('INSERT INTO post_boosts (id, post_id, user_id, budget_coins, duration_days, goal, status, expires_at) VALUES (?,?,?,?,?,?,?,?)',
      [boostId, req.params.id, req.userId, coins, duration_days, goal, 'active', new Date(Date.now() + duration_days * 86400000)]);
    const estimated = Math.round(budget * 200 * duration_days);
    res.json({ success: true, boost_id: boostId, estimated_reach: estimated, coins_spent: coins });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── NEARBY USERS (location-based social)
r.get('/users/nearby', authenticate, async (req, res) => {
  try {
    const { lat, lng, radius = 50 } = req.query;
    if (!lat || !lng) return res.json({ success: true, users: [] });
    // Uses Haversine formula
    const users = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_verified, u.location,
        (6371 * acos(cos(radians(?)) * cos(radians(u.lat)) * cos(radians(u.lng) - radians(?)) + sin(radians(?)) * sin(radians(u.lat)))) AS distance_km
      FROM users u
      WHERE u.id != ? AND u.lat IS NOT NULL AND u.lng IS NOT NULL
        AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      HAVING distance_km < ?
      ORDER BY distance_km ASC LIMIT 20
    `, [lat, lng, lat, req.userId, req.userId, radius]);
    res.json({ success: true, users });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── CONTENT MODERATION (report queue for admins)
r.post('/interactions/report', authenticate, async (req, res) => {
  try {
    const { target_type, target_id, reason, details } = req.body;
    if (!target_type || !target_id || !reason) return res.status(400).json({ success: false, message: 'Missing fields' });
    await db.query('INSERT INTO reports (id, reporter_id, target_type, target_id, reason, details) VALUES (?,?,?,?,?,?)',
      [uuidv4(), req.userId, target_type, target_id, reason, details || null]);
    res.json({ success: true, message: 'Report submitted. Thank you for helping keep RedOrrange safe.' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── CLOSE FRIENDS
r.get('/close-friends', authenticate, async (req, res) => {
  try {
    const friends = await db.query(`
      SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_online, u.is_verified
      FROM close_friends cf JOIN users u ON cf.friend_id=u.id
      WHERE cf.user_id=? ORDER BY u.display_name
    `, [req.userId]);
    res.json({ success: true, friends });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/close-friends/add', authenticate, async (req, res) => {
  try {
    const { user_id } = req.body;
    await db.query('INSERT INTO close_friends (user_id, friend_id) VALUES (?,?)', [req.userId, user_id]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.delete('/close-friends/:id', authenticate, async (req, res) => {
  await db.query('DELETE FROM close_friends WHERE user_id=? AND friend_id=?', [req.userId, req.params.id]);
  res.json({ success: true });
});

// ── LIVE STREAMS
r.post('/live/start', authenticate, async (req, res) => {
  try {
    const { title } = req.body;
    const id = uuidv4();
    await db.query('INSERT INTO live_streams (id, user_id, title, status) VALUES (?,?,?,?)', [id, req.userId, title || 'Live', 'live']);
    if (req.io) req.io.to(`user_${req.userId}`).emit('live_started', { stream_id: id, user_id: req.userId });
    res.json({ success: true, stream_id: id, rtmp_url: `rtmp://live.redorrange.app/live/${id}` });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.post('/live/:id/end', authenticate, async (req, res) => {
  try {
    await db.query("UPDATE live_streams SET status='ended', ended_at=NOW() WHERE id=? AND user_id=?", [req.params.id, req.userId]);
    if (req.io) req.io.to(`live_${req.params.id}`).emit('live_ended', { stream_id: req.params.id });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

r.get('/live', authenticate, async (req, res) => {
  try {
    const streams = await db.query(`
      SELECT ls.*, u.username, u.display_name, u.avatar_url, u.is_verified
      FROM live_streams ls JOIN users u ON ls.user_id=u.id
      WHERE ls.status='live'
        AND ls.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      ORDER BY ls.viewer_count DESC
    `, [req.userId]);
    streams.forEach(s => { s.is_verified = !!s.is_verified; });
    res.json({ success: true, streams });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = r;
