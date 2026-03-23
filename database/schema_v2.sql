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
