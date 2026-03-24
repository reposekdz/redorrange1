'use strict';
/**
 * RedOrrange Recommendation Engine
 * Powers: Feed ranking, Explore discovery, User suggestions, Content scoring
 */
const db = require('../config/database');

// ─────────────────────────────────────────────────────
// FEED RANKING ALGORITHM
// ─────────────────────────────────────────────────────
async function getRankedFeed(userId, page = 1, limit = 15) {
  const offset = (page - 1) * limit;

  const [userInterests, recentViewed, followingIds] = await Promise.all([
    db.query(`
      SELECT ph.name, COUNT(*) AS w
      FROM post_hashtags pth
      JOIN hashtags ph ON pth.hashtag_id=ph.id
      JOIN likes l ON pth.post_id=l.target_id AND l.target_type='post' AND l.user_id=?
      GROUP BY ph.id, ph.name ORDER BY w DESC LIMIT 20
    `, [userId]),
    db.query(`
      SELECT post_id FROM post_views WHERE user_id=? ORDER BY viewed_at DESC LIMIT 100
    `, [userId]).catch(() => []),
    db.query(`SELECT following_id FROM follows WHERE follower_id=? AND status='accepted'`, [userId]),
  ]);

  const viewedIds    = recentViewed.map(v => v.post_id);
  const followingArr = followingIds.map(f => f.following_id);
  followingArr.push(userId);

  const followingPlaceholders = followingArr.length > 0 ? followingArr.map(() => '?').join(',') : 'NULL';
  const viewedPlaceholders    = viewedIds.length > 0    ? viewedIds.map(() => '?').join(',')    : 'NULL';

  const candidates = await db.query(`
    SELECT * FROM (
      SELECT
        p.id, p.user_id, p.caption, p.created_at, p.type, p.location,
        p.likes_count, p.comments_count, p.shares_count, p.views_count,
        p.is_public, p.allow_comments,
        u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS is_liked,
        (SELECT COUNT(*) > 0 FROM saved_posts WHERE post_id=p.id AND user_id=?) AS is_saved,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index ASC LIMIT 1) AS thumbnail,
        (SELECT json_agg(json_build_object('media_url',pm.media_url,'media_type',pm.media_type,'order_index',pm.order_index) ORDER BY pm.order_index) FROM post_media pm WHERE pm.post_id=p.id) AS media,
        CASE WHEN p.user_id IN (${followingPlaceholders}) THEN 3 ELSE 0 END AS rel_score,
        1.0 / (1.0 + EXTRACT(EPOCH FROM (NOW() - p.created_at))/3600.0 * 0.1) AS recency_score,
        CASE WHEN p.views_count > 0 THEN
          (p.likes_count + p.comments_count * 2 + p.shares_count * 3)::float / p.views_count
        ELSE 0 END AS engagement_rate
      FROM posts p
      JOIN users u ON p.user_id = u.id
      WHERE p.is_deleted = FALSE
        AND p.type NOT IN ('reel','story')
        AND p.id NOT IN (${viewedPlaceholders})
        AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
        AND (
          p.user_id IN (${followingPlaceholders})
          OR (p.is_public = TRUE AND p.created_at > NOW() - INTERVAL '7 days')
        )
    ) scored
    ORDER BY
      (rel_score * 0.25) + (recency_score * 0.25) + (engagement_rate * 0.35) +
      (CASE WHEN is_verified THEN 0.1 ELSE 0 END) DESC,
      created_at DESC
    LIMIT ? OFFSET ?
  `, [
    userId, userId,
    ...followingArr,
    ...viewedIds,
    userId,
    ...followingArr,
    limit + 5, offset
  ]);

  const processed = candidates.slice(0, limit).map(p => {
    p.is_liked    = !!p.is_liked;
    p.is_saved    = !!p.is_saved;
    p.is_verified = !!p.is_verified;
    if (typeof p.media === 'string') {
      try { p.media = JSON.parse(p.media) || []; } catch { p.media = []; }
    }
    p.media = (p.media || []).sort((a, b) => (a.order_index || 0) - (b.order_index || 0));
    delete p.rel_score; delete p.recency_score; delete p.engagement_rate;
    return p;
  });

  if (processed.length > 0 && userId) {
    for (const p of processed) {
      db.query(
        `INSERT INTO post_views (post_id, user_id, viewed_at) VALUES (?,?,NOW()) ON CONFLICT DO NOTHING`,
        [p.id, userId]
      ).catch(() => {});
    }
  }

  return { posts: processed, has_more: candidates.length > limit, page, algorithm: 'ranked_v2' };
}

// ─────────────────────────────────────────────────────
// EXPLORE / TRENDING ALGORITHM
// ─────────────────────────────────────────────────────
async function getTrending(userId, limit = 30) {
  const posts = await db.query(`
    SELECT
      p.id, p.user_id, p.caption, p.created_at, p.type,
      p.likes_count, p.comments_count, p.views_count,
      u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
      (SELECT media_type FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS media_type,
      (
        (SELECT COUNT(*) FROM likes WHERE target_type='post' AND target_id=p.id AND created_at > NOW() - INTERVAL '24 hours')
        + (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND created_at > NOW() - INTERVAL '24 hours') * 2
        + (SELECT COUNT(*) FROM shares WHERE post_id=p.id AND created_at > NOW() - INTERVAL '24 hours') * 3
      )::float / GREATEST(1, EXTRACT(EPOCH FROM (NOW() - p.created_at))/3600.0) AS velocity,
      (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS is_liked
    FROM posts p
    JOIN users u ON p.user_id = u.id
    WHERE p.is_public = TRUE
      AND p.is_deleted = FALSE
      AND p.type NOT IN ('reel','story')
      AND p.created_at > NOW() - INTERVAL '7 days'
      AND p.user_id != ?
      AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    ORDER BY velocity DESC, p.views_count DESC
    LIMIT ?
  `, [userId, userId, userId, limit]);

  posts.forEach(p => { p.is_liked = !!p.is_liked; p.is_verified = !!p.is_verified; });
  return posts;
}

// ─────────────────────────────────────────────────────
// USER RECOMMENDATION ALGORITHM
// ─────────────────────────────────────────────────────
async function getSuggestedUsers(userId, limit = 10) {
  const suggested = await db.query(`
    SELECT * FROM (
      SELECT
        u.id, u.username, u.display_name, u.avatar_url, u.bio, u.is_verified,
        u.followers_count,
        (SELECT COUNT(*) FROM follows f1
          JOIN follows f2 ON f1.following_id=f2.following_id
          WHERE f1.follower_id=? AND f2.follower_id=u.id AND f1.status='accepted' AND f2.status='accepted'
        ) AS mutual_follows,
        (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id) AS is_following
      FROM users u
      WHERE u.id != ?
        AND u.username IS NOT NULL
        AND u.id NOT IN (SELECT following_id FROM follows WHERE follower_id=? AND status='accepted')
        AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
        AND u.id NOT IN (SELECT user_id FROM blocks WHERE blocked_id=?)
    ) ranked
    ORDER BY
      mutual_follows * 3 DESC,
      followers_count * 0.01 DESC,
      is_verified DESC
    LIMIT ?
  `, [userId, userId, userId, userId, userId, userId, limit * 2]);

  const seen = new Set();
  const result = [];
  for (const u of suggested) {
    if (!seen.has(u.id) && !u.is_following) {
      seen.add(u.id);
      u.is_verified  = !!u.is_verified;
      u.is_following = !!u.is_following;
      result.push(u);
      if (result.length >= limit) break;
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────
// TRENDING HASHTAGS
// ─────────────────────────────────────────────────────
async function getTrendingHashtags(limit = 20) {
  return db.query(`
    SELECT
      h.id, h.name, h.posts_count,
      COUNT(pth.post_id) AS recent_posts,
      COUNT(pth.post_id)::float / GREATEST(1, h.posts_count) AS trend_score
    FROM hashtags h
    JOIN post_hashtags pth ON h.id = pth.hashtag_id
    JOIN posts p ON pth.post_id = p.id
    WHERE p.created_at > NOW() - INTERVAL '48 hours'
      AND p.is_public = TRUE AND p.is_deleted = FALSE
    GROUP BY h.id, h.name, h.posts_count
    ORDER BY recent_posts DESC, h.posts_count DESC
    LIMIT ?
  `, [limit]);
}

// ─────────────────────────────────────────────────────
// CONTENT QUALITY SCORING
// ─────────────────────────────────────────────────────
function calculateQualityScore(post) {
  let score = 0;
  if (post.caption && post.caption.length > 50)  score += 1;
  if (post.caption && post.caption.length > 150) score += 1;
  if (post.media && post.media.length > 1)       score += 1;
  if (post.location)                             score += 0.5;
  if (post.views_count > 100)                   score += 1;
  if (post.likes_count / Math.max(post.views_count, 1) > 0.05) score += 2;
  return score;
}

// ─────────────────────────────────────────────────────
// SEARCH RELEVANCE SCORING
// ─────────────────────────────────────────────────────
async function searchWithRelevance(query, userId, { type = 'all', page = 1, limit = 20 } = {}) {
  const q      = query.trim();
  const search = `%${q}%`;
  const exact  = q.toLowerCase();
  const offset = (page - 1) * limit;

  if (!q) return { users: [], posts: [], hashtags: [], reels: [], events: [] };

  db.query(
    `INSERT INTO search_history (user_id, query) VALUES (?,?) ON CONFLICT (user_id, query) DO UPDATE SET created_at=NOW()`,
    [userId, q]
  ).catch(() => {});

  const [users, hashtags, posts, reels, events] = await Promise.all([
    (type === 'all' || type === 'users') ? db.query(`
      SELECT
        u.id, u.username, u.display_name, u.avatar_url, u.bio, u.is_verified, u.followers_count,
        (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id) AS is_following,
        (CASE WHEN LOWER(u.username)=? THEN 10 WHEN u.username ILIKE ? THEN 5 ELSE 1 END
         + u.followers_count * 0.001 + CASE WHEN u.is_verified THEN 3 ELSE 0 END) AS relevance
      FROM users u
      WHERE (u.username ILIKE ? OR u.display_name ILIKE ?) AND u.username IS NOT NULL
        AND u.id != ? AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      ORDER BY relevance DESC LIMIT 15
    `, [userId, exact, search, search, search, userId, userId]) : Promise.resolve([]),

    (type === 'all' || type === 'hashtags') ? db.query(
      `SELECT * FROM hashtags WHERE name ILIKE ? ORDER BY CASE WHEN LOWER(name)=? THEN 1 ELSE 2 END, posts_count DESC LIMIT 15`,
      [search, exact]
    ) : Promise.resolve([]),

    (type === 'all' || type === 'posts') ? db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
        p.likes_count * 0.001 AS relevance
      FROM posts p JOIN users u ON p.user_id=u.id
      WHERE p.caption ILIKE ?
        AND p.is_public=TRUE AND p.is_deleted=FALSE
        AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      ORDER BY relevance DESC, p.created_at DESC LIMIT ? OFFSET ?
    `, [search, userId, limit, offset]) : Promise.resolve([]),

    (type === 'all' || type === 'reels') ? db.query(`
      SELECT r.*, u.username, u.display_name, u.avatar_url FROM reels r JOIN users u ON r.user_id=u.id
      WHERE r.caption ILIKE ? AND r.is_public=TRUE ORDER BY r.views_count DESC LIMIT 8
    `, [search]) : Promise.resolve([]),

    (type === 'all' || type === 'events') ? db.query(`
      SELECT e.*, u.username, u.display_name FROM events e JOIN users u ON e.creator_id=u.id
      WHERE (e.title ILIKE ? OR e.description ILIKE ?) AND e.event_type='public'
      ORDER BY e.start_datetime ASC LIMIT 5
    `, [search, search]) : Promise.resolve([]),
  ]);

  users.forEach(u => { u.is_following = !!u.is_following; u.is_verified = !!u.is_verified; delete u.relevance; });
  posts.forEach(p => { p.is_verified = !!p.is_verified; delete p.relevance; });

  return { users, hashtags, posts, reels, events, query: q };
}

// ─────────────────────────────────────────────────────
// REELS RECOMMENDATION
// ─────────────────────────────────────────────────────
async function getRankedReels(userId, page = 1, limit = 10) {
  const offset = (page - 1) * limit;
  const reels = await db.query(`
    SELECT
      r.*, u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT COUNT(*) > 0 FROM likes WHERE target_type='reel' AND target_id=r.id AND user_id=?) AS is_liked,
      (SELECT COUNT(*) > 0 FROM reel_saves WHERE reel_id=r.id AND user_id=?) AS is_saved,
      (SELECT COUNT(*) FROM comments WHERE target_type='reel' AND target_id=r.id) AS comments_count,
      (
        1.0 / (1.0 + EXTRACT(EPOCH FROM (NOW() - r.created_at))/3600.0 * 0.05)
        + r.likes_count * 0.001
        + r.views_count * 0.0001
        + (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=r.user_id AND status='accepted')::int * 2
      ) AS rank_score
    FROM reels r
    JOIN users u ON r.user_id=u.id
    WHERE r.is_public=TRUE AND r.is_deleted=FALSE
      AND r.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    ORDER BY rank_score DESC, r.created_at DESC
    LIMIT ? OFFSET ?
  `, [userId, userId, userId, userId, limit, offset]);

  reels.forEach(r => {
    r.is_liked    = !!r.is_liked;
    r.is_saved    = !!r.is_saved;
    r.is_verified = !!r.is_verified;
    delete r.rank_score;
  });
  return reels;
}

// ─────────────────────────────────────────────────────
// SIMILAR CONTENT
// ─────────────────────────────────────────────────────
async function getSimilarPosts(postId, userId, limit = 6) {
  const tags = await db.query(`SELECT hashtag_id FROM post_hashtags WHERE post_id=?`, [postId]);
  const tagIds = tags.map(t => t.hashtag_id);

  if (tagIds.length === 0) {
    return db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
      FROM posts p JOIN users u ON p.user_id=u.id
      WHERE p.id != ? AND p.is_public=TRUE AND p.is_deleted=FALSE
      ORDER BY p.likes_count DESC LIMIT ?
    `, [postId, limit]);
  }

  const placeholders = tagIds.map(() => '?').join(',');
  return db.query(`
    SELECT p.*, u.username, u.display_name, u.avatar_url,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
      COUNT(pth.hashtag_id) AS shared_tags
    FROM posts p
    JOIN users u ON p.user_id=u.id
    JOIN post_hashtags pth ON p.id=pth.post_id
    WHERE pth.hashtag_id IN (${placeholders})
      AND p.id != ? AND p.is_public=TRUE AND p.is_deleted=FALSE
      AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    GROUP BY p.id, u.username, u.display_name, u.avatar_url
    ORDER BY shared_tags DESC, p.likes_count DESC
    LIMIT ?
  `, [...tagIds, postId, userId, limit]);
}

// ─────────────────────────────────────────────────────
// NOTIFICATION INTELLIGENCE
// ─────────────────────────────────────────────────────
async function shouldNotify(userId, type, actorId, targetId) {
  if (userId === actorId) return false;

  const recent = await db.queryOne(`
    SELECT COUNT(*) AS c FROM notifications
    WHERE user_id=? AND actor_id=? AND type=? AND created_at > NOW() - INTERVAL '1 hour'
  `, [userId, actorId, type]);
  if (recent?.c >= 3) return false;

  const prefs = await db.queryOne('SELECT * FROM notification_preferences WHERE user_id=?', [userId]).catch(() => null);
  if (prefs) {
    const map = { like:'likes', comment:'comments', follow:'follows', message:'messages', call:'calls' };
    const key = map[type];
    if (key && prefs[key] === false) return false;
  }

  return true;
}

// ─────────────────────────────────────────────────────
// ENGAGEMENT RATE CALCULATOR
// ─────────────────────────────────────────────────────
async function getUserEngagementRate(userId, days = 30) {
  const stats = await db.queryOne(`
    SELECT
      COUNT(DISTINCT p.id) AS posts,
      COALESCE(AVG(p.likes_count), 0) AS avg_likes,
      COALESCE(AVG(p.comments_count), 0) AS avg_comments,
      COALESCE(AVG(p.views_count), 1) AS avg_views
    FROM posts p
    WHERE p.user_id=? AND p.created_at > NOW() - INTERVAL '1 day' * ? AND p.is_deleted=FALSE
  `, [userId, days]);

  if (!stats || stats.posts === 0) return 0;
  const rate = ((stats.avg_likes + stats.avg_comments * 2) / Math.max(stats.avg_views, 1)) * 100;
  return Math.min(100, parseFloat(rate.toFixed(2)));
}

// ─────────────────────────────────────────────────────
// VIRAL COEFFICIENT
// ─────────────────────────────────────────────────────
function predictVirality(post) {
  let score = 0;
  const hourAge = (Date.now() - new Date(post.created_at).getTime()) / 3600000;
  const velocity = (post.likes_count + post.comments_count * 2) / Math.max(hourAge, 0.1);
  if (velocity > 10)  score += 3;
  if (velocity > 50)  score += 3;
  if (velocity > 200) score += 4;
  if (post.shares_count > 10) score += 2;
  if (post.is_verified)       score += 1;
  return Math.min(10, score);
}

module.exports = {
  getRankedFeed, getTrending, getSuggestedUsers, getTrendingHashtags,
  searchWithRelevance, getRankedReels, getSimilarPosts,
  shouldNotify, getUserEngagementRate, predictVirality, calculateQualityScore,
};
