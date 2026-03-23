'use strict';
/**
 * RedOrrange Recommendation Engine
 * Powers: Feed ranking, Explore discovery, User suggestions, Content scoring
 */
const db = require('../config/database');

// ─────────────────────────────────────────────────────
// FEED RANKING ALGORITHM
// ─────────────────────────────────────────────────────
/**
 * Score = (engagement_rate * 0.35) + (recency * 0.25) + (relationship * 0.25) + (quality * 0.15)
 * engagement_rate = (likes + comments*2 + shares*3 + saves*2) / max(views, 1)
 * recency         = exponential decay: 1 / (1 + hours_since_post * 0.1)
 * relationship    = mutual_follows + recent_interactions + shared_interests
 * quality         = media_quality + caption_length + hashtag_count
 */
async function getRankedFeed(userId, page = 1, limit = 15) {
  const offset = (page - 1) * limit;
  const now = new Date();

  // Get user's interaction history for personalization
  const [userInterests, recentViewed, followingIds] = await Promise.all([
    db.query(`
      SELECT ph.name, COUNT(*) AS w
      FROM post_hashtags pth
      JOIN hashtags ph ON pth.hashtag_id=ph.id
      JOIN likes l ON pth.post_id=l.target_id AND l.target_type='post' AND l.user_id=?
      GROUP BY ph.id ORDER BY w DESC LIMIT 20
    `, [userId]),
    db.query(`
      SELECT post_id FROM post_views WHERE user_id=? ORDER BY viewed_at DESC LIMIT 100
    `, [userId]).catch(() => []),
    db.query(`SELECT following_id FROM follows WHERE follower_id=? AND status='accepted'`, [userId]),
  ]);

  const viewedIds    = recentViewed.map(v => v.post_id);
  const interestTags = userInterests.map(i => i.name);
  const followingArr = followingIds.map(f => f.following_id);
  followingArr.push(userId); // include own posts

  // Build candidate pool
  const candidates = await db.query(`
    SELECT
      p.id, p.user_id, p.caption, p.created_at, p.type, p.location,
      p.likes_count, p.comments_count, p.shares_count, p.views_count,
      p.is_public, p.allow_comments,
      u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS is_liked,
      (SELECT COUNT(*) > 0 FROM saved_posts WHERE post_id=p.id AND user_id=?) AS is_saved,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index ASC LIMIT 1) AS thumbnail,
      (SELECT JSON_ARRAYAGG(JSON_OBJECT('media_url',pm.media_url,'media_type',pm.media_type,'order_index',pm.order_index)) FROM post_media pm WHERE pm.post_id=p.id ORDER BY pm.order_index) AS media,
      -- Relationship score
      CASE WHEN p.user_id IN (${followingArr.length > 0 ? followingArr.map(() => '?').join(',') : 'NULL'}) THEN 3 ELSE 0 END AS rel_score,
      -- Recency score (decay)
      1.0 / (1.0 + TIMESTAMPDIFF(HOUR, p.created_at, NOW()) * 0.1) AS recency_score,
      -- Engagement rate
      CASE WHEN p.views_count > 0 THEN
        (p.likes_count + p.comments_count * 2 + p.shares_count * 3) / p.views_count
      ELSE 0 END AS engagement_rate
    FROM posts p
    JOIN users u ON p.user_id = u.id
    WHERE p.is_deleted = 0
      AND p.type NOT IN ('reel','story')
      AND p.id NOT IN (${viewedIds.length > 0 ? viewedIds.map(() => '?').join(',') : 'NULL'})
      AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      AND (
        p.user_id IN (${followingArr.length > 0 ? followingArr.map(() => '?').join(',') : 'NULL'})
        OR (p.is_public = 1 AND p.created_at > DATE_SUB(NOW(), INTERVAL 7 DAY))
      )
    ORDER BY
      (rel_score * 0.25) + (recency_score * 0.25) + (engagement_rate * 0.35) +
      (CASE WHEN p.is_verified THEN 0.1 ELSE 0 END) DESC,
      p.created_at DESC
    LIMIT ? OFFSET ?
  `, [
    userId, userId,
    ...followingArr,
    ...viewedIds,
    userId,
    ...followingArr,
    limit + 5, offset  // fetch a bit extra for filtering
  ]);

  // Post-process: parse JSON, booleans, inject variety
  const processed = candidates.slice(0, limit).map(p => {
    p.is_liked  = !!p.is_liked;
    p.is_saved  = !!p.is_saved;
    p.is_verified = !!p.is_verified;
    if (typeof p.media === 'string') {
      try { p.media = JSON.parse(p.media) || []; } catch { p.media = []; }
    }
    p.media = (p.media || []).sort((a, b) => (a.order_index || 0) - (b.order_index || 0));
    delete p.rel_score; delete p.recency_score; delete p.engagement_rate;
    return p;
  });

  // Track that user saw these (async, don't await)
  if (processed.length > 0 && userId) {
    const vals = processed.map(p => `('${p.id}','${userId}',NOW())`).join(',');
    db.query(`INSERT IGNORE INTO post_views (post_id, user_id, viewed_at) VALUES ${vals}`).catch(() => {});
  }

  return { posts: processed, has_more: candidates.length > limit, page, algorithm: 'ranked_v2' };
}

// ─────────────────────────────────────────────────────
// EXPLORE / TRENDING ALGORITHM
// ─────────────────────────────────────────────────────
async function getTrending(userId, limit = 30) {
  // Trending score = engagement velocity (actions in last 24h / post age in hours)
  const posts = await db.query(`
    SELECT
      p.id, p.user_id, p.caption, p.created_at, p.type,
      p.likes_count, p.comments_count, p.views_count,
      u.username, u.display_name, u.avatar_url, u.is_verified,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
      (SELECT media_type FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS media_type,
      -- Velocity: actions per hour since post
      (
        (SELECT COUNT(*) FROM likes WHERE target_type='post' AND target_id=p.id AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR))
        + (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)) * 2
        + (SELECT COUNT(*) FROM shares WHERE post_id=p.id AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)) * 3
      ) / GREATEST(1, TIMESTAMPDIFF(HOUR, p.created_at, NOW())) AS velocity,
      (SELECT COUNT(*) > 0 FROM likes WHERE target_type='post' AND target_id=p.id AND user_id=?) AS is_liked
    FROM posts p
    JOIN users u ON p.user_id = u.id
    WHERE p.is_public = 1
      AND p.is_deleted = 0
      AND p.type NOT IN ('reel','story')
      AND p.created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
      AND p.user_id != ?
      AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    HAVING velocity > 0
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
  /**
   * Score = mutual_followers * 3 + shared_interests * 2 + engagement_with_my_content * 5 + popular * 1
   */
  const suggested = await db.query(`
    SELECT
      u.id, u.username, u.display_name, u.avatar_url, u.bio, u.is_verified,
      u.followers_count,
      -- Mutual followers count
      (SELECT COUNT(*) FROM follows f1
        JOIN follows f2 ON f1.following_id=f2.following_id
        WHERE f1.follower_id=? AND f2.follower_id=u.id AND f1.status='accepted' AND f2.status='accepted'
      ) AS mutual_follows,
      -- Already following check
      (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id) AS is_following
    FROM users u
    WHERE u.id != ?
      AND u.username IS NOT NULL
      AND u.id NOT IN (SELECT following_id FROM follows WHERE follower_id=? AND status='accepted')
      AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      AND u.id NOT IN (SELECT user_id FROM blocks WHERE blocked_id=?)
    ORDER BY
      mutual_follows * 3 DESC,
      u.followers_count * 0.01 DESC,
      u.is_verified DESC
    LIMIT ?
  `, [userId, userId, userId, userId, userId, userId, limit * 2]);

  // Filter and deduplicate
  const seen = new Set();
  const result = [];
  for (const u of suggested) {
    if (!seen.has(u.id) && !u.is_following) {
      seen.add(u.id);
      u.is_verified = !!u.is_verified;
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
      COUNT(pth.post_id) / GREATEST(1, h.posts_count) AS trend_score
    FROM hashtags h
    JOIN post_hashtags pth ON h.id = pth.hashtag_id
    JOIN posts p ON pth.post_id = p.id
    WHERE p.created_at > DATE_SUB(NOW(), INTERVAL 48 HOUR)
      AND p.is_public = 1 AND p.is_deleted = 0
    GROUP BY h.id
    ORDER BY recent_posts DESC, h.posts_count DESC
    LIMIT ?
  `, [limit]);
}

// ─────────────────────────────────────────────────────
// CONTENT QUALITY SCORING
// ─────────────────────────────────────────────────────
function calculateQualityScore(post) {
  let score = 0;
  if (post.caption && post.caption.length > 50) score += 1;
  if (post.caption && post.caption.length > 150) score += 1;
  if (post.media && post.media.length > 1) score += 1;
  if (post.location) score += 0.5;
  if (post.views_count > 100) score += 1;
  if (post.likes_count / Math.max(post.views_count, 1) > 0.05) score += 2;
  return score;
}

// ─────────────────────────────────────────────────────
// SEARCH RELEVANCE SCORING
// ─────────────────────────────────────────────────────
async function searchWithRelevance(query, userId, { type = 'all', page = 1, limit = 20 } = {}) {
  const q       = query.trim();
  const search  = `%${q}%`;
  const exact   = q.toLowerCase();
  const offset  = (page - 1) * limit;

  if (!q) return { users: [], posts: [], hashtags: [], reels: [], events: [] };

  // Log search
  db.query('INSERT INTO search_history (user_id, query) VALUES (?,?) ON DUPLICATE KEY UPDATE created_at=NOW()', [userId, q]).catch(() => {});

  const [users, hashtags, posts, reels, events] = await Promise.all([
    (type === 'all' || type === 'users') ? db.query(`
      SELECT
        u.id, u.username, u.display_name, u.avatar_url, u.bio, u.is_verified, u.followers_count,
        (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=u.id) AS is_following,
        (CASE WHEN LOWER(u.username)=? THEN 10 WHEN u.username LIKE ? THEN 5 ELSE 1 END
         + u.followers_count * 0.001 + IF(u.is_verified, 3, 0)) AS relevance
      FROM users u
      WHERE (u.username LIKE ? OR u.display_name LIKE ?) AND u.username IS NOT NULL
        AND u.id != ? AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      ORDER BY relevance DESC LIMIT 15
    `, [userId, exact, search, search, search, userId, userId]) : Promise.resolve([]),

    (type === 'all' || type === 'hashtags') ? db.query(
      `SELECT * FROM hashtags WHERE name LIKE ? ORDER BY CASE WHEN LOWER(name)=? THEN 1 ELSE 2 END, posts_count DESC LIMIT 15`,
      [search, exact]
    ) : Promise.resolve([]),

    (type === 'all' || type === 'posts') ? db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url, u.is_verified,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
        (MATCH(p.caption) AGAINST(? IN BOOLEAN MODE) + p.likes_count * 0.001) AS relevance
      FROM posts p JOIN users u ON p.user_id=u.id
      WHERE (p.caption LIKE ? OR MATCH(p.caption) AGAINST(? IN BOOLEAN MODE))
        AND p.is_public=1 AND p.is_deleted=0
        AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
      ORDER BY relevance DESC, p.created_at DESC LIMIT ? OFFSET ?
    `, [q, search, q, userId, limit, offset]).catch(() =>
      // Fallback if FULLTEXT not available
      db.query(`
        SELECT p.*, u.username, u.display_name, u.avatar_url,
          (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
        FROM posts p JOIN users u ON p.user_id=u.id
        WHERE p.caption LIKE ? AND p.is_public=1 AND p.is_deleted=0 LIMIT ? OFFSET ?
      `, [search, limit, offset])
    ),

    (type === 'all' || type === 'reels') ? db.query(`
      SELECT r.*, u.username, u.display_name, u.avatar_url FROM reels r JOIN users u ON r.user_id=u.id
      WHERE r.caption LIKE ? AND r.is_public=1 ORDER BY r.views_count DESC LIMIT 8
    `, [search]) : Promise.resolve([]),

    (type === 'all' || type === 'events') ? db.query(`
      SELECT e.*, u.username, u.display_name FROM events e JOIN users u ON e.creator_id=u.id
      WHERE (e.title LIKE ? OR e.description LIKE ?) AND e.event_type='public'
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
      -- Ranking: recency + engagement velocity + following boost
      (
        1.0 / (1.0 + TIMESTAMPDIFF(HOUR, r.created_at, NOW()) * 0.05)
        + r.likes_count * 0.001
        + r.views_count * 0.0001
        + (SELECT COUNT(*) > 0 FROM follows WHERE follower_id=? AND following_id=r.user_id AND status='accepted') * 2
      ) AS rank_score
    FROM reels r
    JOIN users u ON r.user_id=u.id
    WHERE r.is_public=1 AND r.is_deleted=0
      AND r.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    ORDER BY rank_score DESC, r.created_at DESC
    LIMIT ? OFFSET ?
  `, [userId, userId, userId, userId, limit, offset]);

  reels.forEach(r => {
    r.is_liked   = !!r.is_liked;
    r.is_saved   = !!r.is_saved;
    r.is_verified = !!r.is_verified;
    delete r.rank_score;
  });
  return reels;
}

// ─────────────────────────────────────────────────────
// SIMILAR CONTENT
// ─────────────────────────────────────────────────────
async function getSimilarPosts(postId, userId, limit = 6) {
  // Get hashtags of the post
  const tags = await db.query(`
    SELECT hashtag_id FROM post_hashtags WHERE post_id=?
  `, [postId]);
  const tagIds = tags.map(t => t.hashtag_id);

  if (tagIds.length === 0) {
    return db.query(`
      SELECT p.*, u.username, u.display_name, u.avatar_url,
        (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail
      FROM posts p JOIN users u ON p.user_id=u.id
      WHERE p.id != ? AND p.is_public=1 AND p.is_deleted=0
      ORDER BY p.likes_count DESC LIMIT ?
    `, [postId, limit]);
  }

  return db.query(`
    SELECT p.*, u.username, u.display_name, u.avatar_url,
      (SELECT media_url FROM post_media WHERE post_id=p.id ORDER BY order_index LIMIT 1) AS thumbnail,
      COUNT(pth.hashtag_id) AS shared_tags
    FROM posts p
    JOIN users u ON p.user_id=u.id
    JOIN post_hashtags pth ON p.id=pth.post_id
    WHERE pth.hashtag_id IN (${tagIds.map(() => '?').join(',')})
      AND p.id != ? AND p.is_public=1 AND p.is_deleted=0
      AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=?)
    GROUP BY p.id
    ORDER BY shared_tags DESC, p.likes_count DESC
    LIMIT ?
  `, [...tagIds, postId, userId, limit]);
}

// ─────────────────────────────────────────────────────
// NOTIFICATION INTELLIGENCE — batch & deduplicate
// ─────────────────────────────────────────────────────
async function shouldNotify(userId, type, actorId, targetId) {
  // Don't notify self
  if (userId === actorId) return false;

  // Rate limit: max 3 same-type notifications from same actor per hour
  const recent = await db.queryOne(`
    SELECT COUNT(*) AS c FROM notifications
    WHERE user_id=? AND actor_id=? AND type=? AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
  `, [userId, actorId, type]);
  if (recent?.c >= 3) return false;

  // Check user preferences
  const prefs = await db.queryOne('SELECT * FROM notification_preferences WHERE user_id=?', [userId]).catch(() => null);
  if (prefs) {
    const map = { like:'likes', comment:'comments', follow:'follows', message:'messages', call:'calls' };
    const key = map[type];
    if (key && prefs[key] === 0) return false;
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
    WHERE p.user_id=? AND p.created_at > DATE_SUB(NOW(), INTERVAL ? DAY) AND p.is_deleted=0
  `, [userId, days]);

  if (!stats || stats.posts === 0) return 0;
  const rate = ((stats.avg_likes + stats.avg_comments * 2) / Math.max(stats.avg_views, 1)) * 100;
  return Math.min(100, parseFloat(rate.toFixed(2)));
}

// ─────────────────────────────────────────────────────
// VIRAL COEFFICIENT — predict virality
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
