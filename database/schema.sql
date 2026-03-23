-- ================================================================
-- RedOrrange Database Schema v2.1 - Complete
-- All tables needed for full functionality
-- ================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ── USERS
CREATE TABLE IF NOT EXISTS users (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  phone_number    VARCHAR(20) UNIQUE NOT NULL,
  username        VARCHAR(50) UNIQUE,
  display_name    VARCHAR(100),
  bio             TEXT,
  avatar_url      VARCHAR(600),
  cover_url       VARCHAR(600),
  website         VARCHAR(300),
  location        VARCHAR(200),
  gender          ENUM('male','female','other','prefer_not_to_say'),
  status_text     VARCHAR(200),
  last_seen       TIMESTAMP NULL,
  is_online       TINYINT(1) DEFAULT 0,
  is_verified     TINYINT(1) DEFAULT 0,
  is_private      TINYINT(1) DEFAULT 0,
  needs_setup     TINYINT(1) DEFAULT 1,
  posts_count     INT DEFAULT 0,
  reels_count     INT DEFAULT 0,
  followers_count INT DEFAULT 0,
  following_count INT DEFAULT 0,
  read_receipts        TINYINT(1) DEFAULT 1,
  show_online_status   TINYINT(1) DEFAULT 1,
  show_last_seen       TINYINT(1) DEFAULT 1,
  who_can_message      ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_call         ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_see_stories  ENUM('everyone','followers','close_friends') DEFAULT 'everyone',
  is_boosted      TINYINT(1) DEFAULT 0,
  boost_ends_at   TIMESTAMP NULL,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_username    (username),
  INDEX idx_phone       (phone_number),
  INDEX idx_online      (is_online),
  INDEX idx_verified    (is_verified)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── USER SETTINGS (per-user config)
CREATE TABLE IF NOT EXISTS user_settings (
  id                  INT AUTO_INCREMENT PRIMARY KEY,
  user_id             VARCHAR(36) UNIQUE NOT NULL,
  two_factor_enabled  TINYINT(1) DEFAULT 0,
  biometric_enabled   TINYINT(1) DEFAULT 0,
  login_alerts        TINYINT(1) DEFAULT 1,
  read_receipts       TINYINT(1) DEFAULT 1,
  show_online_status  TINYINT(1) DEFAULT 1,
  show_last_seen      TINYINT(1) DEFAULT 1,
  who_can_message     ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_call        ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_see_stories ENUM('everyone','followers','close_friends') DEFAULT 'everyone',
  app_language        VARCHAR(10) DEFAULT 'en',
  theme_mode          ENUM('light','dark','system') DEFAULT 'system',
  auto_download_wifi   JSON,
  auto_download_mobile JSON,
  font_size           FLOAT DEFAULT 1.0,
  disappearing_messages INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── NOTIFICATION PREFERENCES
CREATE TABLE IF NOT EXISTS notification_preferences (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  user_id          VARCHAR(36) UNIQUE NOT NULL,
  messages         TINYINT(1) DEFAULT 1,
  likes            TINYINT(1) DEFAULT 1,
  comments         TINYINT(1) DEFAULT 1,
  follows          TINYINT(1) DEFAULT 1,
  story_views      TINYINT(1) DEFAULT 1,
  mentions         TINYINT(1) DEFAULT 1,
  calls            TINYINT(1) DEFAULT 1,
  events           TINYINT(1) DEFAULT 1,
  live             TINYINT(1) DEFAULT 1,
  marketplace      TINYINT(1) DEFAULT 0,
  channel_posts    TINYINT(1) DEFAULT 1,
  email_digest     TINYINT(1) DEFAULT 0,
  push_enabled     TINYINT(1) DEFAULT 1,
  quiet_hours_start TIME DEFAULT NULL,
  quiet_hours_end   TIME DEFAULT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── PUSH TOKENS
CREATE TABLE IF NOT EXISTS push_tokens (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  token      VARCHAR(500) UNIQUE NOT NULL,
  platform   ENUM('android','ios','web') DEFAULT 'android',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user (user_id)
);

-- ── OTP CODES
CREATE TABLE IF NOT EXISTS otp_codes (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  phone_number VARCHAR(20) NOT NULL,
  code         VARCHAR(10) NOT NULL,
  is_used      TINYINT(1) DEFAULT 0,
  attempts     INT DEFAULT 0,
  expires_at   TIMESTAMP NOT NULL,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_phone_time (phone_number, created_at)
);

-- ── AUTH TOKENS
CREATE TABLE IF NOT EXISTS auth_tokens (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       VARCHAR(36) NOT NULL,
  refresh_token VARCHAR(500) UNIQUE NOT NULL,
  device_info   VARCHAR(300),
  ip_address    VARCHAR(45),
  last_used     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at    TIMESTAMP NOT NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── QR SESSIONS
CREATE TABLE IF NOT EXISTS qr_sessions (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36),
  status     ENUM('pending','scanned','confirmed','expired') DEFAULT 'pending',
  scanned_by VARCHAR(36),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- ── FOLLOWS
CREATE TABLE IF NOT EXISTS follows (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  follower_id  VARCHAR(36) NOT NULL,
  following_id VARCHAR(36) NOT NULL,
  status       ENUM('pending','accepted','declined') DEFAULT 'accepted',
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_follow (follower_id, following_id),
  FOREIGN KEY (follower_id)  REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (following_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_follower  (follower_id),
  INDEX idx_following (following_id)
);

-- ── BLOCKS
CREATE TABLE IF NOT EXISTS blocks (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  blocker_id VARCHAR(36) NOT NULL,
  blocked_id VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_block (blocker_id, blocked_id),
  FOREIGN KEY (blocker_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (blocked_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── CONTACTS
CREATE TABLE IF NOT EXISTS contacts (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL,
  contact_id   VARCHAR(36) NOT NULL,
  nickname     VARCHAR(100),
  is_favorite  TINYINT(1) DEFAULT 0,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_contact (user_id, contact_id),
  FOREIGN KEY (user_id)    REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (contact_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── CLOSE FRIENDS
CREATE TABLE IF NOT EXISTS close_friends (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  friend_id   VARCHAR(36) NOT NULL,
  added_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_cf (user_id, friend_id),
  FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── POSTS
CREATE TABLE IF NOT EXISTS posts (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id         VARCHAR(36) NOT NULL,
  caption         TEXT,
  location        VARCHAR(200),
  type            ENUM('image','video','carousel','text','reel','story') DEFAULT 'image',
  is_public       TINYINT(1) DEFAULT 1,
  allow_comments  TINYINT(1) DEFAULT 1,
  allow_sharing   TINYINT(1) DEFAULT 1,
  is_boosted      TINYINT(1) DEFAULT 0,
  boost_budget    DECIMAL(10,2) DEFAULT 0,
  boost_ends_at   TIMESTAMP NULL,
  is_deleted      TINYINT(1) DEFAULT 0,
  likes_count     INT DEFAULT 0,
  comments_count  INT DEFAULT 0,
  shares_count    INT DEFAULT 0,
  views_count     INT DEFAULT 0,
  saves_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_created (user_id, created_at DESC),
  INDEX idx_public       (is_public, is_deleted, created_at DESC)
);

-- ── POST MEDIA
CREATE TABLE IF NOT EXISTS post_media (
  id            VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  post_id       VARCHAR(36) NOT NULL,
  media_url     VARCHAR(600) NOT NULL,
  media_type    ENUM('image','video') DEFAULT 'image',
  thumbnail_url VARCHAR(600),
  width         INT,
  height        INT,
  duration      INT,
  file_size     INT,
  order_index   INT DEFAULT 0,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- ── LIKES (unified - posts, comments, reels)
CREATE TABLE IF NOT EXISTS likes (
  id             VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id        VARCHAR(36) NOT NULL,
  target_type    ENUM('post','comment','reel','story') NOT NULL,
  target_id      VARCHAR(36) NOT NULL,
  reaction_type  ENUM('like','love','haha','wow','sad','angry') DEFAULT 'like',
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_like (user_id, target_type, target_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_target (target_type, target_id)
);

-- ── COMMENTS
CREATE TABLE IF NOT EXISTS comments (
  id            VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id       VARCHAR(36) NOT NULL,
  target_type   ENUM('post','reel') NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  parent_id     VARCHAR(36) DEFAULT NULL,
  content       TEXT NOT NULL,
  is_deleted    TINYINT(1) DEFAULT 0,
  likes_count   INT DEFAULT 0,
  replies_count INT DEFAULT 0,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_target  (target_type, target_id),
  INDEX idx_parent  (parent_id)
);

-- ── SHARES
CREATE TABLE IF NOT EXISTS shares (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  post_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_share (user_id, post_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- ── SAVED POSTS
CREATE TABLE IF NOT EXISTS saved_posts (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       VARCHAR(36) NOT NULL,
  post_id       VARCHAR(36) NOT NULL,
  collection    VARCHAR(100) DEFAULT 'All Posts',
  saved_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_save (user_id, post_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- ── HASHTAGS
CREATE TABLE IF NOT EXISTS hashtags (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  name        VARCHAR(100) UNIQUE NOT NULL,
  posts_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_posts (posts_count DESC)
);

CREATE TABLE IF NOT EXISTS post_hashtags (
  post_id     VARCHAR(36) NOT NULL,
  hashtag_id  VARCHAR(36) NOT NULL,
  PRIMARY KEY (post_id, hashtag_id),
  FOREIGN KEY (post_id)    REFERENCES posts(id)    ON DELETE CASCADE,
  FOREIGN KEY (hashtag_id) REFERENCES hashtags(id) ON DELETE CASCADE
);

-- ── STORIES
CREATE TABLE IF NOT EXISTS stories (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id      VARCHAR(36) NOT NULL,
  media_url    VARCHAR(600),
  media_type   ENUM('image','video','text') DEFAULT 'image',
  caption      VARCHAR(500),
  text_overlay TEXT,
  bg_color     VARCHAR(20) DEFAULT '#FF6B35',
  music_title  VARCHAR(200),
  music_artist VARCHAR(200),
  music_url    VARCHAR(600),
  duration     INT DEFAULT 5,
  views_count  INT DEFAULT 0,
  type         ENUM('public','close_friends','private') DEFAULT 'public',
  expires_at   TIMESTAMP NOT NULL,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_expires (user_id, expires_at)
);

CREATE TABLE IF NOT EXISTS story_views (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  story_id   VARCHAR(36) NOT NULL,
  viewer_id  VARCHAR(36) NOT NULL,
  viewed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_view (story_id, viewer_id),
  FOREIGN KEY (story_id)  REFERENCES stories(id) ON DELETE CASCADE,
  FOREIGN KEY (viewer_id) REFERENCES users(id)   ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story_replies (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  story_id   VARCHAR(36) NOT NULL,
  sender_id  VARCHAR(36) NOT NULL,
  content    TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (story_id)  REFERENCES stories(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(id)   ON DELETE CASCADE
);

-- ── HIGHLIGHTS
CREATE TABLE IF NOT EXISTS highlights (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  title      VARCHAR(100) NOT NULL,
  cover_url  VARCHAR(600),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS highlight_stories (
  highlight_id VARCHAR(36) NOT NULL,
  story_id     VARCHAR(36) NOT NULL,
  order_index  INT DEFAULT 0,
  PRIMARY KEY (highlight_id, story_id),
  FOREIGN KEY (highlight_id) REFERENCES highlights(id) ON DELETE CASCADE
);

-- ── REELS
CREATE TABLE IF NOT EXISTS reels (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id      VARCHAR(36) NOT NULL,
  video_url    VARCHAR(600) NOT NULL,
  thumbnail_url VARCHAR(600),
  caption      TEXT,
  music_title  VARCHAR(200),
  music_artist VARCHAR(200),
  music_url    VARCHAR(600),
  text_overlay TEXT,
  duration     INT,
  views_count  INT DEFAULT 0,
  likes_count  INT DEFAULT 0,
  comments_count INT DEFAULT 0,
  shares_count INT DEFAULT 0,
  saves_count  INT DEFAULT 0,
  is_deleted   TINYINT(1) DEFAULT 0,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_created (user_id, created_at DESC),
  INDEX idx_views        (views_count DESC)
);

CREATE TABLE IF NOT EXISTS reel_hashtags (
  reel_id    VARCHAR(36) NOT NULL,
  hashtag_id VARCHAR(36) NOT NULL,
  PRIMARY KEY (reel_id, hashtag_id),
  FOREIGN KEY (reel_id)    REFERENCES reels(id)    ON DELETE CASCADE,
  FOREIGN KEY (hashtag_id) REFERENCES hashtags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS reel_saves (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  reel_id    VARCHAR(36) NOT NULL,
  saved_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_save (user_id, reel_id)
);

-- ── CONVERSATIONS & MESSAGES
CREATE TABLE IF NOT EXISTS conversations (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  type            ENUM('direct','group','channel') DEFAULT 'direct',
  name            VARCHAR(200),
  description     TEXT,
  avatar_url      VARCHAR(600),
  created_by      VARCHAR(36),
  last_message_id VARCHAR(36),
  last_message_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_announcement TINYINT(1) DEFAULT 0,
  disappearing_timer INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_last_msg (last_message_at DESC)
);

CREATE TABLE IF NOT EXISTS conversation_members (
  id                   INT AUTO_INCREMENT PRIMARY KEY,
  conversation_id      VARCHAR(36) NOT NULL,
  user_id              VARCHAR(36) NOT NULL,
  role                 ENUM('owner','admin','member') DEFAULT 'member',
  last_read_message_id VARCHAR(36),
  muted_until          TIMESTAMP NULL,
  is_archived          TINYINT(1) DEFAULT 0,
  is_pinned            TINYINT(1) DEFAULT 0,
  disappearing_timer   INT DEFAULT 0,
  joined_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  left_at              TIMESTAMP NULL,
  UNIQUE KEY uq_member (conversation_id, user_id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)         REFERENCES users(id)          ON DELETE CASCADE,
  INDEX idx_user (user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id                VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  conversation_id   VARCHAR(36) NOT NULL,
  sender_id         VARCHAR(36) NOT NULL,
  type              ENUM('text','image','video','audio','voice_note','file','location','contact','sticker','gif','poll','system','deleted') DEFAULT 'text',
  content           TEXT,
  media_url         VARCHAR(600),
  media_thumbnail   VARCHAR(600),
  media_name        VARCHAR(255),
  media_mime        VARCHAR(100),
  media_duration    INT,
  media_size        INT,
  latitude          DECIMAL(10,8),
  longitude         DECIMAL(11,8),
  contact_name      VARCHAR(200),
  contact_phone     VARCHAR(50),
  reply_to_id       VARCHAR(36),
  reply_content     TEXT,
  reply_type        VARCHAR(20),
  reply_sender_name VARCHAR(100),
  reply_sender_username VARCHAR(50),
  is_forwarded      TINYINT(1) DEFAULT 0,
  is_edited         TINYINT(1) DEFAULT 0,
  is_deleted        TINYINT(1) DEFAULT 0,
  deleted_for_all   TINYINT(1) DEFAULT 0,
  expires_at        TIMESTAMP NULL,
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id)       REFERENCES users(id)          ON DELETE CASCADE,
  INDEX idx_conv_created (conversation_id, created_at DESC),
  INDEX idx_expires      (expires_at)
);

CREATE TABLE IF NOT EXISTS message_status (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message_id VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  status     ENUM('sent','delivered','seen') DEFAULT 'delivered',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_status (message_id, user_id),
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS message_reactions (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message_id VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_reaction (message_id, user_id, emoji),
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS pinned_messages (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  conversation_id VARCHAR(36) NOT NULL,
  message_id      VARCHAR(36) NOT NULL,
  pinned_by       VARCHAR(36) NOT NULL,
  pinned_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_pin (conversation_id, message_id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS starred_messages (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  message_id VARCHAR(36) NOT NULL,
  starred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_star (user_id, message_id),
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- ── SCHEDULED MESSAGES
CREATE TABLE IF NOT EXISTS scheduled_messages (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  conversation_id VARCHAR(36) NOT NULL,
  sender_id       VARCHAR(36) NOT NULL,
  type            VARCHAR(20) DEFAULT 'text',
  content         TEXT,
  media_url       VARCHAR(600),
  scheduled_at    TIMESTAMP NOT NULL,
  status          ENUM('pending','sent','failed','cancelled') DEFAULT 'pending',
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id)       REFERENCES users(id)         ON DELETE CASCADE,
  INDEX idx_pending (status, scheduled_at)
);

-- ── CALLS
CREATE TABLE IF NOT EXISTS calls (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  caller_id   VARCHAR(36) NOT NULL,
  callee_id   VARCHAR(36) NOT NULL,
  type        ENUM('audio','video') NOT NULL,
  status      ENUM('calling','ringing','ongoing','ended','rejected','missed','busy') DEFAULT 'calling',
  duration    INT DEFAULT 0,
  started_at  TIMESTAMP NULL,
  ended_at    TIMESTAMP NULL,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (callee_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_caller (caller_id, created_at DESC),
  INDEX idx_callee (callee_id, created_at DESC)
);

-- ── EVENTS
CREATE TABLE IF NOT EXISTS events (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  creator_id      VARCHAR(36) NOT NULL,
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  cover_url       VARCHAR(600),
  event_type      ENUM('public','private','invite_only') DEFAULT 'public',
  start_datetime  TIMESTAMP NOT NULL,
  end_datetime    TIMESTAMP NULL,
  location        VARCHAR(300),
  online_link     VARCHAR(500),
  going_count     INT DEFAULT 0,
  interested_count INT DEFAULT 0,
  views_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_start (start_datetime)
);

CREATE TABLE IF NOT EXISTS event_attendees (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  event_id   VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  status     ENUM('going','interested','not_going') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_attendee (event_id, user_id),
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE
);

-- ── NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) NOT NULL,
  actor_id    VARCHAR(36),
  type        VARCHAR(50) NOT NULL,
  target_type VARCHAR(50),
  target_id   VARCHAR(36),
  message     TEXT,
  is_read     TINYINT(1) DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_read    (user_id, is_read, created_at DESC),
  INDEX idx_user_created (user_id, created_at DESC)
);

-- ── SEARCH HISTORY
CREATE TABLE IF NOT EXISTS search_history (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  query      VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_created (user_id, created_at DESC)
);

-- ── REPORTS
CREATE TABLE IF NOT EXISTS reports (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  reporter_id VARCHAR(36) NOT NULL,
  target_type VARCHAR(30) NOT NULL,
  target_id   VARCHAR(36) NOT NULL,
  reason      VARCHAR(200) NOT NULL,
  details     TEXT,
  status      ENUM('pending','reviewed','resolved','dismissed') DEFAULT 'pending',
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── MARKETPLACE
CREATE TABLE IF NOT EXISTS marketplace_items (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  seller_id       VARCHAR(36) NOT NULL,
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  price           DECIMAL(14,2),
  currency        VARCHAR(5) DEFAULT 'USD',
  category        VARCHAR(80),
  condition_type  ENUM('new','used','refurbished') DEFAULT 'used',
  location        VARCHAR(255),
  images          JSON,
  status          ENUM('active','sold','paused','deleted') DEFAULT 'active',
  views_count     INT DEFAULT 0,
  saves_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (seller_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_status   (status, created_at DESC),
  INDEX idx_category (category, status)
);

CREATE TABLE IF NOT EXISTS marketplace_saves (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  user_id  VARCHAR(36) NOT NULL,
  item_id  VARCHAR(36) NOT NULL,
  saved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_save (user_id, item_id)
);

-- ── CHANNELS
CREATE TABLE IF NOT EXISTS channels (
  id                VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  owner_id          VARCHAR(36) NOT NULL,
  name              VARCHAR(150) NOT NULL,
  description       TEXT,
  avatar_url        VARCHAR(600),
  cover_url         VARCHAR(600),
  category          VARCHAR(50),
  is_verified       TINYINT(1) DEFAULT 0,
  subscribers_count INT DEFAULT 0,
  posts_count       INT DEFAULT 0,
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS channel_subscriptions (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  channel_id    VARCHAR(36) NOT NULL,
  user_id       VARCHAR(36) NOT NULL,
  subscribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_sub (channel_id, user_id)
);

CREATE TABLE IF NOT EXISTS channel_posts (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  channel_id  VARCHAR(36) NOT NULL,
  content     TEXT,
  media_url   VARCHAR(600),
  media_type  ENUM('image','video','text','file') DEFAULT 'text',
  views_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
);

-- ── LIVE STREAMS
CREATE TABLE IF NOT EXISTS live_streams (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id      VARCHAR(36) NOT NULL,
  title        VARCHAR(255),
  stream_key   VARCHAR(100) UNIQUE,
  status       ENUM('scheduled','live','ended') DEFAULT 'live',
  viewer_count INT DEFAULT 0,
  peak_viewers INT DEFAULT 0,
  started_at   TIMESTAMP NULL,
  ended_at     TIMESTAMP NULL,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_status (status, created_at DESC)
);

CREATE TABLE IF NOT EXISTS live_comments (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  stream_id  VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  content    VARCHAR(500) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)   REFERENCES users(id)        ON DELETE CASCADE
);

-- ── POLLS
CREATE TABLE IF NOT EXISTS polls (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  post_id    VARCHAR(36) NOT NULL,
  question   TEXT NOT NULL,
  expires_at TIMESTAMP,
  multiple   TINYINT(1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS poll_options (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  poll_id    VARCHAR(36) NOT NULL,
  text       VARCHAR(255) NOT NULL,
  votes      INT DEFAULT 0,
  order_idx  INT DEFAULT 0,
  FOREIGN KEY (poll_id) REFERENCES polls(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS poll_votes (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  poll_id    VARCHAR(36) NOT NULL,
  option_id  INT NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_vote (poll_id, user_id, option_id)
);

-- ── USER ANALYTICS
CREATE TABLE IF NOT EXISTS user_analytics (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  user_id          VARCHAR(36) NOT NULL,
  date             DATE NOT NULL,
  profile_views    INT DEFAULT 0,
  post_impressions INT DEFAULT 0,
  story_views      INT DEFAULT 0,
  reel_views       INT DEFAULT 0,
  link_clicks      INT DEFAULT 0,
  new_followers    INT DEFAULT 0,
  UNIQUE KEY uq_analytics (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── INNOVATIONS (unique features not in WhatsApp)

-- ── MOODS (status system with expiry)
CREATE TABLE IF NOT EXISTS user_moods (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) UNIQUE NOT NULL,
  mood_type  VARCHAR(50),
  mood_text  VARCHAR(200),
  mood_icon  VARCHAR(10),
  expires_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── COLLABORATIVE POSTS (multiple creators)
CREATE TABLE IF NOT EXISTS post_collaborators (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  post_id  VARCHAR(36) NOT NULL,
  user_id  VARCHAR(36) NOT NULL,
  status   ENUM('pending','accepted','declined') DEFAULT 'pending',
  added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_collab (post_id, user_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── CONTENT COLLECTIONS (save to boards)
CREATE TABLE IF NOT EXISTS collections (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) NOT NULL,
  name        VARCHAR(100) NOT NULL,
  cover_url   VARCHAR(600),
  is_private  TINYINT(1) DEFAULT 0,
  items_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS collection_items (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  collection_id VARCHAR(36) NOT NULL,
  target_type   ENUM('post','reel') NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  added_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_item (collection_id, target_type, target_id),
  FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
);

-- ── MESSAGE THREADS (reply threads like Slack)
CREATE TABLE IF NOT EXISTS message_threads (
  id               VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  parent_message_id VARCHAR(36) NOT NULL,
  conversation_id  VARCHAR(36) NOT NULL,
  replies_count    INT DEFAULT 0,
  last_reply_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_thread (parent_message_id),
  FOREIGN KEY (parent_message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- ── AI SMART REPLIES CACHE
CREATE TABLE IF NOT EXISTS ai_suggestions (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  message_id  VARCHAR(36) NOT NULL,
  suggestions JSON,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- ── POST BOOSTS
CREATE TABLE IF NOT EXISTS post_boosts (
  id            VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  post_id       VARCHAR(36) NOT NULL,
  user_id       VARCHAR(36) NOT NULL,
  budget        DECIMAL(10,2) DEFAULT 0,
  currency      VARCHAR(5) DEFAULT 'USD',
  status        ENUM('active','paused','ended') DEFAULT 'active',
  impressions   INT DEFAULT 0,
  clicks        INT DEFAULT 0,
  starts_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ends_at       TIMESTAMP,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── USER BADGES
CREATE TABLE IF NOT EXISTS user_badges (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  badge_type ENUM('early_adopter','creator','verified','moderator','top_fan','100_posts','viral','top_seller') NOT NULL,
  awarded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_badge (user_id, badge_type),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── DISAPPEARING MESSAGES LOG
CREATE TABLE IF NOT EXISTS disappeared_messages (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  message_id  VARCHAR(36) NOT NULL,
  expired_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── LINK PREVIEWS CACHE
CREATE TABLE IF NOT EXISTS link_previews (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  url         VARCHAR(1000) NOT NULL,
  title       VARCHAR(300),
  description TEXT,
  image_url   VARCHAR(600),
  site_name   VARCHAR(100),
  fetched_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_url (url(255))
);

-- ── USER TAGS IN POSTS
CREATE TABLE IF NOT EXISTS post_tags (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  post_id    VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tag (post_id, user_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── STORY HIGHLIGHTS
-- (already above as highlights + highlight_stories)

-- ── INDEXES
CREATE INDEX IF NOT EXISTS idx_msgs_conv ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_unread ON notifications(user_id, is_read, created_at DESC);

SET FOREIGN_KEY_CHECKS = 1;

-- ══════════════════════════════════════════════════════════════
-- MONETIZATION SYSTEM
-- ══════════════════════════════════════════════════════════════

-- ── COINS (in-app currency)
CREATE TABLE IF NOT EXISTS coin_packages (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  name        VARCHAR(100) NOT NULL,
  coins       INT NOT NULL,
  price_usd   DECIMAL(10,2) NOT NULL,
  price_rwf   DECIMAL(10,2),
  bonus_coins INT DEFAULT 0,
  is_popular  TINYINT(1) DEFAULT 0,
  is_active   TINYINT(1) DEFAULT 1,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO coin_packages (id, name, coins, price_usd, price_rwf, bonus_coins, is_popular) VALUES
  ('cp-1','Starter Pack', 100, 0.99, 1200, 0, 0),
  ('cp-2','Basic Pack',   500, 4.99, 5900, 50, 0),
  ('cp-3','Popular Pack', 1200, 9.99, 11900, 200, 1),
  ('cp-4','Value Pack',   2500, 19.99, 23900, 500, 0),
  ('cp-5','Pro Pack',     6500, 49.99, 59900, 1500, 0),
  ('cp-6','Elite Pack',   14000, 99.99, 119900, 4000, 0);

-- ── USER WALLETS
CREATE TABLE IF NOT EXISTS user_wallets (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id      VARCHAR(36) UNIQUE NOT NULL,
  coins        INT DEFAULT 0,
  locked_coins INT DEFAULT 0,
  total_earned DECIMAL(14,2) DEFAULT 0,
  total_spent  DECIMAL(14,2) DEFAULT 0,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── COIN TRANSACTIONS
CREATE TABLE IF NOT EXISTS coin_transactions (
  id             VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id        VARCHAR(36) NOT NULL,
  type           ENUM('purchase','gift_sent','gift_received','withdrawal','refund','bonus','reward') NOT NULL,
  amount         INT NOT NULL,
  balance_before INT NOT NULL,
  balance_after  INT NOT NULL,
  reference_id   VARCHAR(36),
  reference_type ENUM('gift','purchase','withdrawal','order') DEFAULT 'purchase',
  description    VARCHAR(255),
  metadata       JSON,
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_created (user_id, created_at DESC),
  INDEX idx_type (type)
);

-- ── GIFT CATALOG
CREATE TABLE IF NOT EXISTS gifts (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  name        VARCHAR(100) NOT NULL,
  emoji       VARCHAR(10) NOT NULL,
  icon_url    VARCHAR(600),
  coin_price  INT NOT NULL,
  category    ENUM('basic','premium','special','seasonal') DEFAULT 'basic',
  effect      VARCHAR(50),
  is_active   TINYINT(1) DEFAULT 1,
  sort_order  INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO gifts (id, name, emoji, coin_price, category, sort_order) VALUES
  ('g-1', 'Heart',       '❤️',  10,  'basic',   1),
  ('g-2', 'Rose',        '🌹',  50,  'basic',   2),
  ('g-3', 'Fire',        '🔥',  30,  'basic',   3),
  ('g-4', 'Star',        '⭐',  80,  'basic',   4),
  ('g-5', 'Crown',       '👑',  200, 'premium', 5),
  ('g-6', 'Diamond',     '💎',  500, 'premium', 6),
  ('g-7', 'Rocket',      '🚀',  150, 'premium', 7),
  ('g-8', 'Trophy',      '🏆',  300, 'premium', 8),
  ('g-9', 'Lion',        '🦁',  800, 'special', 9),
  ('g-10','Universe',    '🌌', 1000, 'special', 10),
  ('g-11','Supernova',   '💥', 2000, 'special', 11),
  ('g-12','Luxury Car',  '🏎️', 5000, 'special', 12);

-- ── GIFT TRANSACTIONS (sent gifts)
CREATE TABLE IF NOT EXISTS gift_transactions (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  sender_id   VARCHAR(36) NOT NULL,
  receiver_id VARCHAR(36) NOT NULL,
  gift_id     VARCHAR(36) NOT NULL,
  quantity    INT DEFAULT 1,
  coins_spent INT NOT NULL,
  context_type ENUM('live','reel','post','profile','chat') DEFAULT 'live',
  context_id  VARCHAR(36),
  message     VARCHAR(200),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (sender_id)   REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (gift_id)     REFERENCES gifts(id),
  INDEX idx_receiver (receiver_id, created_at DESC),
  INDEX idx_sender   (sender_id, created_at DESC)
);

-- ── PAYMENT ORDERS
CREATE TABLE IF NOT EXISTS payment_orders (
  id             VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id        VARCHAR(36) NOT NULL,
  package_id     VARCHAR(36) NOT NULL,
  amount_usd     DECIMAL(10,2) NOT NULL,
  amount_local   DECIMAL(10,2),
  currency       VARCHAR(5) DEFAULT 'USD',
  coins          INT NOT NULL,
  bonus_coins    INT DEFAULT 0,
  status         ENUM('pending','processing','completed','failed','refunded') DEFAULT 'pending',
  payment_method ENUM('card','mobile_money','paypal','stripe','mtn','airtel') NOT NULL,
  provider_ref   VARCHAR(200),
  provider_data  JSON,
  failure_reason VARCHAR(300),
  completed_at   TIMESTAMP NULL,
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_status (user_id, status)
);

-- ── ESCROW ORDERS (marketplace)
CREATE TABLE IF NOT EXISTS escrow_orders (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  buyer_id        VARCHAR(36) NOT NULL,
  seller_id       VARCHAR(36) NOT NULL,
  item_id         VARCHAR(36) NOT NULL,
  amount_usd      DECIMAL(14,2) NOT NULL,
  platform_fee    DECIMAL(14,2) NOT NULL,
  seller_receives DECIMAL(14,2) NOT NULL,
  status          ENUM('pending','funded','in_transit','delivered','completed','disputed','refunded','cancelled') DEFAULT 'pending',
  payment_method  VARCHAR(50),
  payment_ref     VARCHAR(200),
  tracking_number VARCHAR(200),
  buyer_confirmed TINYINT(1) DEFAULT 0,
  seller_confirmed TINYINT(1) DEFAULT 0,
  dispute_reason  TEXT,
  dispute_opened_at TIMESTAMP NULL,
  dispute_resolved_at TIMESTAMP NULL,
  auto_release_at TIMESTAMP NULL,
  funded_at       TIMESTAMP NULL,
  completed_at    TIMESTAMP NULL,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (buyer_id)  REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (seller_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (item_id)   REFERENCES marketplace_items(id),
  INDEX idx_buyer  (buyer_id, status),
  INDEX idx_seller (seller_id, status)
);

-- ── ESCROW EVENTS LOG
CREATE TABLE IF NOT EXISTS escrow_events (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  order_id   VARCHAR(36) NOT NULL,
  actor_id   VARCHAR(36),
  event_type ENUM('created','funded','shipped','delivered','confirmed','disputed','resolved','refunded','cancelled','auto_released') NOT NULL,
  details    TEXT,
  metadata   JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES escrow_orders(id) ON DELETE CASCADE,
  INDEX idx_order (order_id)
);

-- ── CREATOR PAYOUTS
CREATE TABLE IF NOT EXISTS creator_payouts (
  id             VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id        VARCHAR(36) NOT NULL,
  amount_usd     DECIMAL(10,2) NOT NULL,
  coins_redeemed INT NOT NULL,
  payout_method  ENUM('bank','mobile_money','paypal','mtn','airtel') NOT NULL,
  account_details JSON,
  status         ENUM('pending','processing','completed','failed') DEFAULT 'pending',
  provider_ref   VARCHAR(200),
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processed_at   TIMESTAMP NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── SUBSCRIPTIONS (premium users)
CREATE TABLE IF NOT EXISTS subscription_plans (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  name         VARCHAR(100) NOT NULL,
  price_usd    DECIMAL(10,2) NOT NULL,
  price_rwf    DECIMAL(10,2),
  duration_days INT NOT NULL,
  features     JSON,
  is_active    TINYINT(1) DEFAULT 1
);

INSERT IGNORE INTO subscription_plans (id, name, price_usd, price_rwf, duration_days, features) VALUES
  ('sp-1', 'RedOrrange Plus',  4.99, 5900, 30, '["No ads","Verified badge","500 monthly coins","Priority support","Exclusive stickers"]'),
  ('sp-2', 'RedOrrange Pro',   9.99, 11900, 30, '["Everything in Plus","2000 monthly coins","Analytics Pro","Custom themes","Creator tools","Revenue sharing"]'),
  ('sp-3', 'RedOrrange Elite', 29.99, 35900, 30, '["Everything in Pro","5000 monthly coins","White glove support","Early features","Creator fund eligible","Promoted content"]');

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) UNIQUE NOT NULL,
  plan_id     VARCHAR(36) NOT NULL,
  status      ENUM('active','cancelled','expired','paused') DEFAULT 'active',
  started_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at  TIMESTAMP NOT NULL,
  auto_renew  TINYINT(1) DEFAULT 1,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES subscription_plans(id)
);

-- ── AUDIT LOG (security)
CREATE TABLE IF NOT EXISTS audit_logs (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36),
  action     VARCHAR(100) NOT NULL,
  resource   VARCHAR(100),
  resource_id VARCHAR(36),
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  details    JSON,
  risk_level ENUM('low','medium','high','critical') DEFAULT 'low',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_user    (user_id, created_at DESC),
  INDEX idx_action  (action),
  INDEX idx_risk    (risk_level, created_at DESC)
);

-- ── RATE LIMITS TABLE (distributed)
CREATE TABLE IF NOT EXISTS rate_limit_log (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  key_name   VARCHAR(200) NOT NULL,
  count      INT DEFAULT 1,
  window_end TIMESTAMP NOT NULL,
  INDEX idx_key_window (key_name, window_end)
);

-- ══════════════════════════════════════════════════════════════
-- ADS SYSTEM — Complete Production Schema
-- ══════════════════════════════════════════════════════════════

-- ── AD ACCOUNTS (businesses/creators who run ads)
CREATE TABLE IF NOT EXISTS ad_accounts (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id         VARCHAR(36) NOT NULL,
  business_name   VARCHAR(200) NOT NULL,
  business_email  VARCHAR(200),
  business_phone  VARCHAR(30),
  website_url     VARCHAR(500),
  category        VARCHAR(100),
  country         VARCHAR(5) DEFAULT 'RW',
  currency        VARCHAR(5) DEFAULT 'USD',
  timezone        VARCHAR(50) DEFAULT 'Africa/Kigali',
  status          ENUM('active','restricted','disabled','pending_review') DEFAULT 'active',
  balance_usd     DECIMAL(14,4) DEFAULT 0,
  total_spent     DECIMAL(14,4) DEFAULT 0,
  credit_limit    DECIMAL(14,4) DEFAULT 100,
  verified        TINYINT(1) DEFAULT 0,
  tax_id          VARCHAR(100),
  billing_address TEXT,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user (user_id),
  INDEX idx_status (status)
);

-- ── AD CAMPAIGNS
CREATE TABLE IF NOT EXISTS ad_campaigns (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  account_id      VARCHAR(36) NOT NULL,
  name            VARCHAR(300) NOT NULL,
  objective       ENUM('awareness','reach','traffic','engagement','leads','conversions','app_installs','video_views','follower_growth','store_visits') NOT NULL,
  status          ENUM('draft','active','paused','completed','archived','rejected','pending_review') DEFAULT 'draft',
  budget_type     ENUM('daily','lifetime') DEFAULT 'daily',
  budget_amount   DECIMAL(12,4) NOT NULL,
  spent_amount    DECIMAL(14,4) DEFAULT 0,
  start_date      DATE NOT NULL,
  end_date        DATE,
  bid_strategy    ENUM('lowest_cost','target_cost','manual_bid','cost_cap') DEFAULT 'lowest_cost',
  bid_amount      DECIMAL(10,4),
  -- targeting
  target_genders  JSON,
  target_age_min  INT DEFAULT 13,
  target_age_max  INT DEFAULT 65,
  target_countries JSON,
  target_cities   JSON,
  target_interests JSON,
  target_languages JSON,
  target_devices  JSON,
  target_platforms JSON,
  -- custom audiences
  custom_audience_ids JSON,
  lookalike_audience_ids JSON,
  -- delivery
  impressions_total BIGINT DEFAULT 0,
  clicks_total    BIGINT DEFAULT 0,
  reach_total     BIGINT DEFAULT 0,
  conversions_total INT DEFAULT 0,
  video_views_total BIGINT DEFAULT 0,
  -- review
  review_notes    TEXT,
  reviewed_by     VARCHAR(36),
  reviewed_at     TIMESTAMP NULL,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (account_id) REFERENCES ad_accounts(id) ON DELETE CASCADE,
  INDEX idx_account (account_id),
  INDEX idx_status  (status),
  INDEX idx_dates   (start_date, end_date)
);

-- ── AD SETS (targeting + placement groups within campaign)
CREATE TABLE IF NOT EXISTS ad_sets (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  campaign_id     VARCHAR(36) NOT NULL,
  name            VARCHAR(300) NOT NULL,
  status          ENUM('active','paused','archived') DEFAULT 'active',
  placements      JSON COMMENT 'feed,stories,reels,explore,chat,live',
  daily_budget    DECIMAL(12,4),
  schedule_type   ENUM('all_time','scheduled') DEFAULT 'all_time',
  schedule_hours  JSON COMMENT 'hours of day to run 0-23',
  frequency_cap   INT DEFAULT 5 COMMENT 'max times per user per day',
  bid_amount      DECIMAL(10,4),
  impressions     BIGINT DEFAULT 0,
  clicks          BIGINT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (campaign_id) REFERENCES ad_campaigns(id) ON DELETE CASCADE,
  INDEX idx_campaign (campaign_id)
);

-- ── ADS (individual ad creatives)
CREATE TABLE IF NOT EXISTS ads (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  ad_set_id       VARCHAR(36) NOT NULL,
  campaign_id     VARCHAR(36) NOT NULL,
  account_id      VARCHAR(36) NOT NULL,
  name            VARCHAR(300) NOT NULL,
  format          ENUM('image','video','carousel','story','reel','collection','text') NOT NULL,
  status          ENUM('draft','active','paused','rejected','archived','pending_review') DEFAULT 'draft',
  -- Creative
  headline        VARCHAR(200),
  primary_text    VARCHAR(500),
  description     VARCHAR(300),
  cta_text        VARCHAR(50) DEFAULT 'Learn More',
  cta_url         VARCHAR(1000),
  display_url     VARCHAR(200),
  -- Media
  media_url       VARCHAR(1000),
  media_thumb_url VARCHAR(1000),
  media_duration  INT,
  media_width     INT,
  media_height    INT,
  media_size      BIGINT,
  -- Carousel items
  carousel_items  JSON,
  -- Story-specific
  story_bg_color  VARCHAR(10),
  story_text_overlay VARCHAR(500),
  -- Review
  rejection_reason VARCHAR(500),
  review_notes    TEXT,
  reviewed_by     VARCHAR(36),
  reviewed_at     TIMESTAMP NULL,
  -- Stats
  impressions     BIGINT DEFAULT 0,
  clicks          BIGINT DEFAULT 0,
  reach           BIGINT DEFAULT 0,
  video_views     BIGINT DEFAULT 0,
  video_pct_25    INT DEFAULT 0,
  video_pct_50    INT DEFAULT 0,
  video_pct_75    INT DEFAULT 0,
  video_pct_100   INT DEFAULT 0,
  link_clicks     INT DEFAULT 0,
  saves           INT DEFAULT 0,
  shares          INT DEFAULT 0,
  reactions       INT DEFAULT 0,
  comments_count  INT DEFAULT 0,
  conversions     INT DEFAULT 0,
  cost_per_click  DECIMAL(10,4),
  cost_per_1000   DECIMAL(10,4),
  spend           DECIMAL(14,4) DEFAULT 0,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (ad_set_id)   REFERENCES ad_sets(id)      ON DELETE CASCADE,
  FOREIGN KEY (campaign_id) REFERENCES ad_campaigns(id) ON DELETE CASCADE,
  FOREIGN KEY (account_id)  REFERENCES ad_accounts(id)  ON DELETE CASCADE,
  INDEX idx_campaign (campaign_id),
  INDEX idx_status   (status),
  INDEX idx_format   (format)
);

-- ── AD IMPRESSIONS (every time an ad is shown)
CREATE TABLE IF NOT EXISTS ad_impressions (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  ad_id       VARCHAR(36) NOT NULL,
  campaign_id VARCHAR(36) NOT NULL,
  user_id     VARCHAR(36),
  placement   ENUM('feed','story','reel','explore','chat','live','search','profile') NOT NULL,
  device_type ENUM('mobile','tablet','desktop','unknown') DEFAULT 'mobile',
  platform    ENUM('android','ios','web','desktop') DEFAULT 'android',
  country     VARCHAR(5),
  city        VARCHAR(100),
  cost        DECIMAL(10,6) DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ad_id) REFERENCES ads(id) ON DELETE CASCADE,
  INDEX idx_ad      (ad_id, created_at DESC),
  INDEX idx_campaign (campaign_id),
  INDEX idx_user    (user_id),
  INDEX idx_date    (DATE(created_at))
);

-- ── AD CLICKS
CREATE TABLE IF NOT EXISTS ad_clicks (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  ad_id       VARCHAR(36) NOT NULL,
  campaign_id VARCHAR(36) NOT NULL,
  user_id     VARCHAR(36),
  placement   VARCHAR(30),
  click_type  ENUM('cta','headline','image','video','swipe') DEFAULT 'cta',
  cost        DECIMAL(10,6) DEFAULT 0,
  ip_address  VARCHAR(45),
  user_agent  VARCHAR(500),
  referrer    VARCHAR(500),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ad_id) REFERENCES ads(id) ON DELETE CASCADE,
  INDEX idx_ad (ad_id, created_at DESC)
);

-- ── AD CONVERSIONS
CREATE TABLE IF NOT EXISTS ad_conversions (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  ad_id           VARCHAR(36) NOT NULL,
  campaign_id     VARCHAR(36) NOT NULL,
  user_id         VARCHAR(36),
  conversion_type ENUM('purchase','signup','follow','install','lead','page_view','custom') NOT NULL,
  conversion_value DECIMAL(14,4),
  currency        VARCHAR(5) DEFAULT 'USD',
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ad_id) REFERENCES ads(id) ON DELETE CASCADE,
  INDEX idx_ad (ad_id)
);

-- ── DAILY AD STATS (aggregated, for fast reporting)
CREATE TABLE IF NOT EXISTS ad_daily_stats (
  id             VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  ad_id          VARCHAR(36) NOT NULL,
  campaign_id    VARCHAR(36) NOT NULL,
  account_id     VARCHAR(36) NOT NULL,
  stat_date      DATE NOT NULL,
  impressions    BIGINT DEFAULT 0,
  clicks         BIGINT DEFAULT 0,
  reach          BIGINT DEFAULT 0,
  spend          DECIMAL(14,4) DEFAULT 0,
  video_views    BIGINT DEFAULT 0,
  conversions    INT DEFAULT 0,
  reactions      INT DEFAULT 0,
  ctr            DECIMAL(8,6) GENERATED ALWAYS AS (IF(impressions>0, clicks/impressions, 0)) STORED,
  cpm            DECIMAL(10,4) GENERATED ALWAYS AS (IF(impressions>0, spend*1000/impressions, 0)) STORED,
  cpc            DECIMAL(10,4) GENERATED ALWAYS AS (IF(clicks>0, spend/clicks, 0)) STORED,
  UNIQUE KEY uq_ad_date (ad_id, stat_date),
  FOREIGN KEY (ad_id) REFERENCES ads(id) ON DELETE CASCADE,
  INDEX idx_campaign_date (campaign_id, stat_date),
  INDEX idx_account_date  (account_id, stat_date)
);

-- ── SAVED ADS (users can save ads)
CREATE TABLE IF NOT EXISTS saved_ads (
  ad_id      VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (ad_id, user_id),
  FOREIGN KEY (ad_id)   REFERENCES ads(id)   ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ── AD HIDDEN (user hides specific ads)
CREATE TABLE IF NOT EXISTS hidden_ads (
  ad_id      VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  reason     ENUM('not_relevant','offensive','seen_too_much','misleading','spam','other') DEFAULT 'not_relevant',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (ad_id, user_id)
);

-- ── AD FEEDBACK (reported ads)
CREATE TABLE IF NOT EXISTS ad_reports (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  ad_id      VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  reason     ENUM('misleading','inappropriate','spam','scam','violent','other') NOT NULL,
  details    TEXT,
  status     ENUM('pending','reviewed','dismissed','actioned') DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ad_id) REFERENCES ads(id) ON DELETE CASCADE,
  INDEX idx_ad (ad_id),
  INDEX idx_status (status)
);

-- ── AD BILLING TRANSACTIONS
CREATE TABLE IF NOT EXISTS ad_billing (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  account_id      VARCHAR(36) NOT NULL,
  campaign_id     VARCHAR(36),
  ad_id           VARCHAR(36),
  type            ENUM('charge','topup','refund','credit','adjustment') NOT NULL,
  amount          DECIMAL(14,4) NOT NULL,
  balance_before  DECIMAL(14,4) NOT NULL,
  balance_after   DECIMAL(14,4) NOT NULL,
  description     VARCHAR(300),
  payment_method  VARCHAR(50),
  payment_ref     VARCHAR(200),
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (account_id) REFERENCES ad_accounts(id) ON DELETE CASCADE,
  INDEX idx_account (account_id, created_at DESC)
);

-- ── CUSTOM AUDIENCES
CREATE TABLE IF NOT EXISTS ad_audiences (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  account_id  VARCHAR(36) NOT NULL,
  name        VARCHAR(200) NOT NULL,
  type        ENUM('custom','lookalike','saved') DEFAULT 'custom',
  source      ENUM('user_list','website_visitors','app_users','engagers','followers') DEFAULT 'engagers',
  size        INT DEFAULT 0,
  description VARCHAR(500),
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (account_id) REFERENCES ad_accounts(id) ON DELETE CASCADE
);

-- ── AD CREATIVE TEMPLATES
CREATE TABLE IF NOT EXISTS ad_templates (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  name        VARCHAR(200) NOT NULL,
  category    VARCHAR(100),
  format      VARCHAR(50),
  preview_url VARCHAR(500),
  config      JSON,
  is_active   TINYINT(1) DEFAULT 1,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample ad templates
INSERT IGNORE INTO ad_templates (id, name, category, format, config) VALUES
  ('tpl-1','Product Showcase','ecommerce','image','{"headline":"{{product_name}}","cta":"Shop Now","bg":"#FFFFFF"}'),
  ('tpl-2','App Install','technology','image','{"headline":"Get the App","cta":"Install","badge":"app_store"}'),
  ('tpl-3','Event Promotion','events','image','{"headline":"{{event_name}}","cta":"Get Tickets","show_date":true}'),
  ('tpl-4','Service Offer','services','image','{"headline":"{{service_name}}","cta":"Book Now","discount":true}'),
  ('tpl-5','Brand Awareness','general','video','{"headline":"{{brand_name}}","cta":"Learn More","autoplay":true}');

-- ── Payment provider references on users table
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(100) AFTER status_text,
  ADD COLUMN IF NOT EXISTS paypal_payer_id VARCHAR(100) AFTER stripe_customer_id;

-- ── Add stripe_price_id to subscription_plans
ALTER TABLE subscription_plans
  ADD COLUMN IF NOT EXISTS stripe_price_id VARCHAR(100) AFTER features;

-- Update subscription plans with sample Stripe Price IDs (replace with real ones)
UPDATE subscription_plans SET stripe_price_id='price_plus_monthly'  WHERE name='RedOrrange Plus';
UPDATE subscription_plans SET stripe_price_id='price_pro_monthly'   WHERE name='RedOrrange Pro';
UPDATE subscription_plans SET stripe_price_id='price_elite_monthly' WHERE name='RedOrrange Elite';

-- ── Post views tracking (for feed algorithm)
CREATE TABLE IF NOT EXISTS post_views (
  post_id    VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  viewed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (post_id, user_id),
  INDEX idx_user (user_id, viewed_at DESC)
);

-- ── User interaction weights (for collaborative filtering)
CREATE TABLE IF NOT EXISTS user_content_signals (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  signal_type ENUM('like','comment','share','save','view','skip','follow','unfollow') NOT NULL,
  target_type ENUM('post','reel','user','hashtag','story') NOT NULL,
  target_id  VARCHAR(36) NOT NULL,
  weight     DECIMAL(5,3) DEFAULT 1.0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_user_type (user_id, signal_type, created_at DESC),
  INDEX idx_target    (target_type, target_id)
);

-- ── Reel saves (if not exists)
CREATE TABLE IF NOT EXISTS reel_saves (
  reel_id    VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reel_id, user_id)
);

-- ── Comments table (if using separate from interactions)
CREATE TABLE IF NOT EXISTS comments (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  target_type ENUM('post','reel','story') DEFAULT 'post',
  target_id   VARCHAR(36) NOT NULL,
  user_id     VARCHAR(36) NOT NULL,
  parent_id   VARCHAR(36) DEFAULT NULL,
  content     TEXT NOT NULL,
  likes_count INT DEFAULT 0,
  is_deleted  TINYINT(1) DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_target (target_type, target_id, is_deleted, created_at DESC),
  INDEX idx_user   (user_id)
);

-- ── Shares table
CREATE TABLE IF NOT EXISTS shares (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  post_id    VARCHAR(36),
  user_id    VARCHAR(36) NOT NULL,
  share_type ENUM('story','message','external','repost') DEFAULT 'external',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_post (post_id, created_at DESC)
);
