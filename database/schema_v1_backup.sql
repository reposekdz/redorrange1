-- ================================================================
-- RedOrrange Social Media Platform - Complete MySQL Schema v2.0
-- ================================================================

CREATE DATABASE IF NOT EXISTS redorrange
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE redorrange;

-- ---- USERS ----
CREATE TABLE users (
  id            VARCHAR(36)  PRIMARY KEY DEFAULT (UUID()),
  phone_number  VARCHAR(25)  UNIQUE NOT NULL,
  country_code  VARCHAR(6)   NOT NULL DEFAULT '+1',
  username      VARCHAR(50)  UNIQUE,
  display_name  VARCHAR(100),
  bio           TEXT,
  avatar_url    VARCHAR(600),
  cover_url     VARCHAR(600),
  website       VARCHAR(300),
  location      VARCHAR(255),
  gender        ENUM('male','female','other','prefer_not'),
  date_of_birth DATE,
  is_verified   TINYINT(1)   DEFAULT 0,
  is_private    TINYINT(1)   DEFAULT 0,
  is_online     TINYINT(1)   DEFAULT 0,
  last_seen     TIMESTAMP    NULL,
  qr_code       VARCHAR(100) UNIQUE,
  push_token    TEXT,
  status_text   VARCHAR(200) DEFAULT 'Hey there! I am using RedOrrange',
  two_fa_enabled TINYINT(1)  DEFAULT 0,
  created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_phone (phone_number),
  INDEX idx_username (username)
);

-- ---- OTP ----
CREATE TABLE otp_codes (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  phone_number VARCHAR(25)  NOT NULL,
  code         VARCHAR(6)   NOT NULL,
  expires_at   TIMESTAMP    NOT NULL,
  verified     TINYINT(1)   DEFAULT 0,
  attempts     INT          DEFAULT 0,
  created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_otp_phone (phone_number)
);

-- ---- QR LOGIN ----
CREATE TABLE qr_sessions (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  qr_token   VARCHAR(120) UNIQUE NOT NULL,
  user_id    VARCHAR(36),
  status     ENUM('pending','scanned','confirmed','expired') DEFAULT 'pending',
  expires_at TIMESTAMP    NOT NULL,
  created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- ---- AUTH TOKENS ----
CREATE TABLE auth_tokens (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  token       TEXT        NOT NULL,
  device_name VARCHAR(100),
  device_type ENUM('mobile','web','desktop') DEFAULT 'mobile',
  ip_address  VARCHAR(45),
  expires_at  TIMESTAMP   NOT NULL,
  created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_token (user_id)
);

-- ---- CONTACTS ----
CREATE TABLE contacts (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL,
  contact_id   VARCHAR(36) NOT NULL,
  nickname     VARCHAR(100),
  is_blocked   TINYINT(1)  DEFAULT 0,
  added_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_contact (user_id, contact_id),
  FOREIGN KEY (user_id)    REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (contact_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- FOLLOWS ----
CREATE TABLE follows (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  follower_id   VARCHAR(36) NOT NULL,
  following_id  VARCHAR(36) NOT NULL,
  status        ENUM('pending','accepted') DEFAULT 'accepted',
  created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_follow (follower_id, following_id),
  FOREIGN KEY (follower_id)  REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (following_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- BLOCKS ----
CREATE TABLE blocks (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  blocker_id VARCHAR(36) NOT NULL,
  blocked_id VARCHAR(36) NOT NULL,
  created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_block (blocker_id, blocked_id),
  FOREIGN KEY (blocker_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (blocked_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- POSTS ----
CREATE TABLE posts (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id         VARCHAR(36) NOT NULL,
  caption         TEXT,
  location        VARCHAR(255),
  type            ENUM('image','video','text','carousel') DEFAULT 'image',
  is_public       TINYINT(1)  DEFAULT 1,
  allow_comments  TINYINT(1)  DEFAULT 1,
  allow_sharing   TINYINT(1)  DEFAULT 1,
  views_count     INT         DEFAULT 0,
  created_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_user_posts (user_id),
  INDEX idx_post_created (created_at DESC)
);

-- ---- POST MEDIA ----
CREATE TABLE post_media (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  post_id       VARCHAR(36) NOT NULL,
  media_url     VARCHAR(600) NOT NULL,
  media_type    ENUM('image','video') NOT NULL,
  thumbnail_url VARCHAR(600),
  width         INT,
  height        INT,
  duration      INT,
  order_index   INT DEFAULT 0,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- ---- POST TAGS ----
CREATE TABLE post_tags (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  post_id VARCHAR(36) NOT NULL,
  user_id VARCHAR(36) NOT NULL,
  x_pos   FLOAT,
  y_pos   FLOAT,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- HASHTAGS ----
CREATE TABLE hashtags (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(100) UNIQUE NOT NULL,
  posts_count INT DEFAULT 0
);

CREATE TABLE post_hashtags (
  post_id    VARCHAR(36) NOT NULL,
  hashtag_id INT         NOT NULL,
  PRIMARY KEY (post_id, hashtag_id),
  FOREIGN KEY (post_id)    REFERENCES posts(id)    ON DELETE CASCADE,
  FOREIGN KEY (hashtag_id) REFERENCES hashtags(id) ON DELETE CASCADE
);

-- ---- LIKES (polymorphic) ----
CREATE TABLE likes (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       VARCHAR(36) NOT NULL,
  target_type   ENUM('post','reel','story','comment','event') NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  reaction_type ENUM('like','love','haha','wow','sad','angry') DEFAULT 'like',
  created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_like (user_id, target_type, target_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_target (target_type, target_id)
);

-- ---- COMMENTS ----
CREATE TABLE comments (
  id            VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id       VARCHAR(36) NOT NULL,
  target_type   ENUM('post','reel','event') NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  parent_id     VARCHAR(36) NULL,
  content       TEXT        NOT NULL,
  likes_count   INT         DEFAULT 0,
  replies_count INT         DEFAULT 0,
  is_deleted    TINYINT(1)  DEFAULT 0,
  created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id)   REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES comments(id) ON DELETE CASCADE,
  INDEX idx_target_comments (target_type, target_id),
  INDEX idx_parent (parent_id)
);

-- ---- SHARES ----
CREATE TABLE shares (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  target_type ENUM('post','reel','event') NOT NULL,
  target_id   VARCHAR(36) NOT NULL,
  platform    ENUM('internal','external','link') DEFAULT 'internal',
  created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- SAVED POSTS ----
CREATE TABLE saved_posts (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  user_id  VARCHAR(36) NOT NULL,
  post_id  VARCHAR(36) NOT NULL,
  saved_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_save (user_id, post_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- ---- STORIES ----
CREATE TABLE stories (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) NOT NULL,
  media_url   VARCHAR(600) NOT NULL,
  media_type  ENUM('image','video') NOT NULL,
  thumbnail_url VARCHAR(600),
  duration    INT         DEFAULT 5,
  caption     TEXT,
  bg_color    VARCHAR(20),
  stickers    JSON,
  views_count INT         DEFAULT 0,
  is_active   TINYINT(1)  DEFAULT 1,
  expires_at  TIMESTAMP   NOT NULL,
  created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_story_user (user_id, is_active),
  INDEX idx_story_expires (expires_at)
);

-- ---- STORY VIEWS ----
CREATE TABLE story_views (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  story_id  VARCHAR(36) NOT NULL,
  viewer_id VARCHAR(36) NOT NULL,
  viewed_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_view (story_id, viewer_id),
  FOREIGN KEY (story_id)  REFERENCES stories(id) ON DELETE CASCADE,
  FOREIGN KEY (viewer_id) REFERENCES users(id)   ON DELETE CASCADE
);

-- ---- STORY REPLIES ----
CREATE TABLE story_replies (
  id        VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  story_id  VARCHAR(36) NOT NULL,
  user_id   VARCHAR(36) NOT NULL,
  content   TEXT,
  media_url VARCHAR(600),
  created_at TIMESTAMP  DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)  REFERENCES users(id)   ON DELETE CASCADE
);

-- ---- HIGHLIGHTS ----
CREATE TABLE highlights (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  title      VARCHAR(100) NOT NULL,
  cover_url  VARCHAR(600),
  order_index INT DEFAULT 0,
  created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE highlight_stories (
  highlight_id VARCHAR(36) NOT NULL,
  story_id     VARCHAR(36) NOT NULL,
  order_index  INT DEFAULT 0,
  added_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (highlight_id, story_id),
  FOREIGN KEY (highlight_id) REFERENCES highlights(id) ON DELETE CASCADE
);

-- ---- REELS ----
CREATE TABLE reels (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id         VARCHAR(36) NOT NULL,
  video_url       VARCHAR(600) NOT NULL,
  thumbnail_url   VARCHAR(600),
  audio_url       VARCHAR(600),
  audio_name      VARCHAR(200),
  caption         TEXT,
  duration        INT,
  views_count     INT         DEFAULT 0,
  likes_count     INT         DEFAULT 0,
  comments_count  INT         DEFAULT 0,
  shares_count    INT         DEFAULT 0,
  is_public       TINYINT(1)  DEFAULT 1,
  created_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_reel_created (created_at DESC),
  INDEX idx_reel_views (views_count DESC)
);

CREATE TABLE reel_hashtags (
  reel_id    VARCHAR(36) NOT NULL,
  hashtag_id INT         NOT NULL,
  PRIMARY KEY (reel_id, hashtag_id),
  FOREIGN KEY (reel_id)    REFERENCES reels(id)    ON DELETE CASCADE,
  FOREIGN KEY (hashtag_id) REFERENCES hashtags(id) ON DELETE CASCADE
);

-- ---- EVENTS ----
CREATE TABLE events (
  id               VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  creator_id       VARCHAR(36) NOT NULL,
  title            VARCHAR(255) NOT NULL,
  description      TEXT,
  cover_url        VARCHAR(600),
  event_type       ENUM('public','private','friends') DEFAULT 'public',
  start_datetime   TIMESTAMP   NOT NULL,
  end_datetime     TIMESTAMP,
  location         VARCHAR(500),
  lat              DECIMAL(10,8),
  lng              DECIMAL(11,8),
  online_link      VARCHAR(600),
  max_attendees    INT,
  going_count      INT         DEFAULT 0,
  interested_count INT         DEFAULT 0,
  created_at       TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_event_start (start_datetime)
);

CREATE TABLE event_attendees (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  event_id   VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  status     ENUM('going','interested','not_going') NOT NULL,
  created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_attendee (event_id, user_id),
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE
);

-- ---- CONVERSATIONS ----
CREATE TABLE conversations (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  type            ENUM('direct','group') DEFAULT 'direct',
  name            VARCHAR(255),
  avatar_url      VARCHAR(600),
  description     TEXT,
  created_by      VARCHAR(36),
  last_message_id VARCHAR(36),
  last_message_at TIMESTAMP NULL,
  created_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_conv_last (last_message_at DESC)
);

CREATE TABLE conversation_members (
  id                    INT AUTO_INCREMENT PRIMARY KEY,
  conversation_id       VARCHAR(36) NOT NULL,
  user_id               VARCHAR(36) NOT NULL,
  role                  ENUM('member','admin','owner') DEFAULT 'member',
  joined_at             TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  left_at               TIMESTAMP NULL,
  muted_until           TIMESTAMP NULL,
  last_read_message_id  VARCHAR(36),
  UNIQUE KEY uq_member (conversation_id, user_id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)         REFERENCES users(id)         ON DELETE CASCADE
);

-- ---- MESSAGES ----
CREATE TABLE messages (
  id               VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  conversation_id  VARCHAR(36) NOT NULL,
  sender_id        VARCHAR(36) NOT NULL,
  type             ENUM('text','image','video','audio','file','voice_note','location','contact','call_log','sticker','gif') NOT NULL DEFAULT 'text',
  content          TEXT,
  media_url        VARCHAR(600),
  media_thumbnail  VARCHAR(600),
  media_duration   INT,
  media_size       BIGINT,
  media_name       VARCHAR(255),
  media_mime       VARCHAR(100),
  latitude         DECIMAL(10,8),
  longitude        DECIMAL(11,8),
  contact_name     VARCHAR(100),
  contact_phone    VARCHAR(25),
  reply_to_id      VARCHAR(36),
  forwarded_from   VARCHAR(36),
  is_edited        TINYINT(1)  DEFAULT 0,
  is_deleted       TINYINT(1)  DEFAULT 0,
  deleted_for_all  TINYINT(1)  DEFAULT 0,
  created_at       TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id)       REFERENCES users(id)         ON DELETE CASCADE,
  FOREIGN KEY (reply_to_id)     REFERENCES messages(id)      ON DELETE SET NULL,
  INDEX idx_conv_msg (conversation_id, created_at)
);

-- ---- MESSAGE STATUS ----
CREATE TABLE message_status (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  message_id  VARCHAR(36) NOT NULL,
  user_id     VARCHAR(36) NOT NULL,
  status      ENUM('sent','delivered','read') DEFAULT 'sent',
  updated_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_msg_status (message_id, user_id),
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE
);

-- ---- MESSAGE REACTIONS ----
CREATE TABLE message_reactions (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message_id VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_react (message_id, user_id),
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE
);

-- ---- CALLS ----
CREATE TABLE calls (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  caller_id       VARCHAR(36) NOT NULL,
  callee_id       VARCHAR(36),
  conversation_id VARCHAR(36),
  type            ENUM('audio','video') NOT NULL,
  status          ENUM('calling','ringing','ongoing','ended','missed','rejected','busy') DEFAULT 'calling',
  started_at      TIMESTAMP NULL,
  ended_at        TIMESTAMP NULL,
  duration        INT DEFAULT 0,
  created_at      TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (callee_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_call_users (caller_id, callee_id)
);

-- ---- NOTIFICATIONS ----
CREATE TABLE notifications (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) NOT NULL,
  actor_id    VARCHAR(36),
  type        ENUM('like','comment','follow','follow_request','mention','tag','story_view','story_reply','reel_like','reel_comment','event_invite','call_missed','message','contact_joined') NOT NULL,
  target_type VARCHAR(50),
  target_id   VARCHAR(36),
  message     TEXT,
  is_read     TINYINT(1)  DEFAULT 0,
  created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_notif_user (user_id, is_read, created_at DESC)
);

-- ---- SEARCH HISTORY ----
CREATE TABLE search_history (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  query      VARCHAR(255) NOT NULL,
  created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_search_user (user_id)
);

-- ---- REPORTS ----
CREATE TABLE reports (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  reporter_id VARCHAR(36) NOT NULL,
  target_type ENUM('user','post','reel','story','comment','event') NOT NULL,
  target_id   VARCHAR(36) NOT NULL,
  reason      VARCHAR(100) NOT NULL,
  description TEXT,
  status      ENUM('pending','reviewed','resolved') DEFAULT 'pending',
  created_at  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- VIEWS ----
CREATE OR REPLACE VIEW v_post_feed AS
SELECT
  p.*,
  u.username, u.display_name, u.avatar_url, u.is_verified,
  (SELECT COUNT(*) FROM likes    WHERE target_type='post' AND target_id=p.id) AS likes_count,
  (SELECT COUNT(*) FROM comments WHERE target_type='post' AND target_id=p.id AND is_deleted=0) AS comments_count,
  (SELECT COUNT(*) FROM shares   WHERE target_type='post' AND target_id=p.id) AS shares_count
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.is_public = 1;

-- ---- INDEXES ----
CREATE INDEX idx_msg_created    ON messages(created_at DESC);
CREATE INDEX idx_story_active   ON stories(is_active, expires_at);
CREATE INDEX idx_reel_popular   ON reels(views_count DESC, created_at DESC);
CREATE INDEX idx_event_upcoming ON events(start_datetime, event_type);
CREATE INDEX idx_notif_created  ON notifications(created_at DESC);
CREATE INDEX idx_hashtag_count  ON hashtags(posts_count DESC);

-- ---- STORED PROCEDURES ----
DELIMITER $$

CREATE PROCEDURE create_notification(
  IN p_user_id     VARCHAR(36),
  IN p_actor_id    VARCHAR(36),
  IN p_type        VARCHAR(50),
  IN p_target_type VARCHAR(50),
  IN p_target_id   VARCHAR(36),
  IN p_message     TEXT
)
BEGIN
  IF p_user_id != p_actor_id THEN
    INSERT INTO notifications (user_id, actor_id, type, target_type, target_id, message)
    VALUES (p_user_id, p_actor_id, p_type, p_target_type, p_target_id, p_message);
  END IF;
END$$

CREATE PROCEDURE cleanup_expired()
BEGIN
  UPDATE stories SET is_active=0 WHERE expires_at < NOW() AND is_active=1;
  DELETE FROM otp_codes    WHERE expires_at < NOW();
  UPDATE qr_sessions SET status='expired' WHERE expires_at < NOW() AND status='pending';
END$$

DELIMITER ;

-- ================================================================
-- ADVANCED FEATURES - Schema Extension v2.1
-- ================================================================

-- ---- POLLS (in posts) ----
CREATE TABLE IF NOT EXISTS polls (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  post_id     VARCHAR(36) NOT NULL,
  question    TEXT NOT NULL,
  expires_at  TIMESTAMP,
  multiple    TINYINT(1) DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
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
  UNIQUE KEY uq_vote (poll_id, user_id, option_id),
  FOREIGN KEY (poll_id)   REFERENCES polls(id)        ON DELETE CASCADE,
  FOREIGN KEY (option_id) REFERENCES poll_options(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)   REFERENCES users(id)        ON DELETE CASCADE
);

-- ---- CHANNELS (broadcast) ----
CREATE TABLE IF NOT EXISTS channels (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  owner_id    VARCHAR(36) NOT NULL,
  name        VARCHAR(150) NOT NULL,
  description TEXT,
  avatar_url  VARCHAR(600),
  cover_url   VARCHAR(600),
  category    VARCHAR(50),
  is_verified TINYINT(1) DEFAULT 0,
  subscribers_count INT DEFAULT 0,
  posts_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_channel_subs (subscribers_count DESC)
);

CREATE TABLE IF NOT EXISTS channel_subscriptions (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  channel_id  VARCHAR(36) NOT NULL,
  user_id     VARCHAR(36) NOT NULL,
  subscribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_sub (channel_id, user_id),
  FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE
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

-- ---- MARKETPLACE ----
CREATE TABLE IF NOT EXISTS marketplace_items (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  seller_id    VARCHAR(36) NOT NULL,
  title        VARCHAR(255) NOT NULL,
  description  TEXT,
  price        DECIMAL(12,2),
  currency     VARCHAR(5) DEFAULT 'USD',
  category     VARCHAR(80),
  condition_type ENUM('new','used','refurbished') DEFAULT 'new',
  location     VARCHAR(255),
  images       JSON,
  status       ENUM('active','sold','paused','deleted') DEFAULT 'active',
  views_count  INT DEFAULT 0,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (seller_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_market_status (status, created_at DESC)
);

CREATE TABLE IF NOT EXISTS marketplace_saves (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  user_id   VARCHAR(36) NOT NULL,
  item_id   VARCHAR(36) NOT NULL,
  saved_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_save (user_id, item_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (item_id) REFERENCES marketplace_items(id) ON DELETE CASCADE
);

-- ---- LIVE STREAMS ----
CREATE TABLE IF NOT EXISTS live_streams (
  id          VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id     VARCHAR(36) NOT NULL,
  title       VARCHAR(255),
  stream_key  VARCHAR(100) UNIQUE,
  rtmp_url    VARCHAR(500),
  hls_url     VARCHAR(500),
  thumbnail   VARCHAR(600),
  status      ENUM('scheduled','live','ended') DEFAULT 'scheduled',
  viewer_count INT DEFAULT 0,
  peak_viewers INT DEFAULT 0,
  started_at  TIMESTAMP NULL,
  ended_at    TIMESTAMP NULL,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
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

-- ---- USER ANALYTICS ----
CREATE TABLE IF NOT EXISTS user_analytics (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  date        DATE NOT NULL,
  profile_views INT DEFAULT 0,
  post_impressions INT DEFAULT 0,
  story_views INT DEFAULT 0,
  reel_views  INT DEFAULT 0,
  link_clicks INT DEFAULT 0,
  new_followers INT DEFAULT 0,
  UNIQUE KEY uq_analytics (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- PIN MESSAGES ----
CREATE TABLE IF NOT EXISTS pinned_messages (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  conversation_id VARCHAR(36) NOT NULL,
  message_id      VARCHAR(36) NOT NULL,
  pinned_by       VARCHAR(36) NOT NULL,
  pinned_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_pin (conversation_id, message_id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id)      REFERENCES messages(id)      ON DELETE CASCADE
);

-- ---- MESSAGE STARRED ----
CREATE TABLE IF NOT EXISTS starred_messages (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  message_id VARCHAR(36) NOT NULL,
  starred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_star (user_id, message_id),
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- ---- MEDIA ALBUMS ----
CREATE TABLE IF NOT EXISTS media_albums (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  name       VARCHAR(100) NOT NULL,
  cover_url  VARCHAR(600),
  media_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- STATUS (WhatsApp-style text statuses) ----
CREATE TABLE IF NOT EXISTS text_statuses (
  id         VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id    VARCHAR(36) NOT NULL,
  content    TEXT NOT NULL,
  bg_color   VARCHAR(20) DEFAULT '#FF6B35',
  font_style VARCHAR(30) DEFAULT 'normal',
  expires_at TIMESTAMP NOT NULL,
  views_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- THREADS (comment threads) ----
-- Already handled by comments.parent_id

-- ---- USER BADGES ----
CREATE TABLE IF NOT EXISTS user_badges (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  badge_type ENUM('early_adopter','creator','verified','moderator','top_fan','100_posts','viral') NOT NULL,
  awarded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_badge (user_id, badge_type),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- LINK PREVIEWS CACHE ----
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

-- ---- SCHEDULED POSTS ----
CREATE TABLE IF NOT EXISTS scheduled_posts (
  id           VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id      VARCHAR(36) NOT NULL,
  caption      TEXT,
  media_urls   JSON,
  post_type    VARCHAR(20) DEFAULT 'image',
  scheduled_at TIMESTAMP NOT NULL,
  status       ENUM('pending','published','failed') DEFAULT 'pending',
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---- CLOSE FRIENDS ----
CREATE TABLE IF NOT EXISTS close_friends (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  user_id   VARCHAR(36) NOT NULL,
  friend_id VARCHAR(36) NOT NULL,
  added_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_cf (user_id, friend_id),
  FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Additional indexes
CREATE INDEX IF NOT EXISTS idx_channels_category  ON channels(category);
CREATE INDEX IF NOT EXISTS idx_market_category     ON marketplace_items(category, status);
CREATE INDEX IF NOT EXISTS idx_live_status         ON live_streams(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_date      ON user_analytics(user_id, date DESC);

-- ================================================================
-- SCHEMA v3.0 — Complete Missing Tables
-- ================================================================

-- Push notification tokens
CREATE TABLE IF NOT EXISTS push_tokens (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL,
  token        VARCHAR(500) NOT NULL,
  platform     ENUM('android','ios','web') DEFAULT 'android',
  device_name  VARCHAR(100),
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_push (user_id, token(255)),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Per-user notification preferences
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id        VARCHAR(36) PRIMARY KEY,
  messages       TINYINT(1) DEFAULT 1,
  likes          TINYINT(1) DEFAULT 1,
  comments       TINYINT(1) DEFAULT 1,
  follows        TINYINT(1) DEFAULT 1,
  story_views    TINYINT(1) DEFAULT 1,
  mentions       TINYINT(1) DEFAULT 1,
  calls          TINYINT(1) DEFAULT 1,
  events         TINYINT(1) DEFAULT 1,
  live           TINYINT(1) DEFAULT 1,
  marketplace    TINYINT(1) DEFAULT 0,
  channel_posts  TINYINT(1) DEFAULT 1,
  email_digest   TINYINT(1) DEFAULT 0,
  push_enabled   TINYINT(1) DEFAULT 1,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Post / reel boosts (paid promotion)
CREATE TABLE IF NOT EXISTS post_boosts (
  id              VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id         VARCHAR(36) NOT NULL,
  post_id         VARCHAR(36),
  reel_id         VARCHAR(36),
  budget          DECIMAL(10,2) DEFAULT 0.00,
  currency        VARCHAR(5) DEFAULT 'USD',
  duration_days   INT DEFAULT 7,
  target_audience JSON,
  impressions     INT DEFAULT 0,
  clicks          INT DEFAULT 0,
  status          ENUM('pending','active','paused','completed','cancelled') DEFAULT 'active',
  started_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ends_at         TIMESTAMP,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- User settings (extended)
CREATE TABLE IF NOT EXISTS user_settings (
  user_id             VARCHAR(36) PRIMARY KEY,
  two_factor_enabled  TINYINT(1) DEFAULT 0,
  biometric_enabled   TINYINT(1) DEFAULT 0,
  login_alerts        TINYINT(1) DEFAULT 1,
  read_receipts       TINYINT(1) DEFAULT 1,
  show_online_status  TINYINT(1) DEFAULT 1,
  show_last_seen      TINYINT(1) DEFAULT 1,
  who_can_message     ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_call        ENUM('everyone','followers','nobody') DEFAULT 'everyone',
  who_can_see_stories ENUM('everyone','followers','close_friends','nobody') DEFAULT 'everyone',
  app_language        VARCHAR(10) DEFAULT 'en',
  theme_mode          ENUM('light','dark','system') DEFAULT 'system',
  auto_download_wifi  TINYINT(1) DEFAULT 1,
  auto_download_mobile TINYINT(1) DEFAULT 0,
  font_size           FLOAT DEFAULT 1.0,
  created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Message forwards (track forwarded messages)
CREATE TABLE IF NOT EXISTS message_forwards (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  original_msg_id VARCHAR(36) NOT NULL,
  new_msg_id      VARCHAR(36) NOT NULL,
  forwarded_by    VARCHAR(36) NOT NULL,
  to_conv_id      VARCHAR(36) NOT NULL,
  forwarded_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (forwarded_by) REFERENCES users(id) ON DELETE CASCADE
);

-- Reel comments (uses existing comments table with target_type='reel')
-- But add reel_views tracking
CREATE TABLE IF NOT EXISTS reel_views (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  reel_id    VARCHAR(36) NOT NULL,
  viewer_id  VARCHAR(36) NOT NULL,
  watched_pct TINYINT DEFAULT 0,  -- 0-100 percent watched
  viewed_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_reel_view (reel_id, viewer_id),
  FOREIGN KEY (reel_id)   REFERENCES reels(id) ON DELETE CASCADE,
  FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Story reactions (emoji reactions to stories)
CREATE TABLE IF NOT EXISTS story_reactions (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  story_id   VARCHAR(36) NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_story_react (story_id, user_id),
  FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id)  REFERENCES users(id)   ON DELETE CASCADE
);

-- Linked devices
CREATE TABLE IF NOT EXISTS linked_devices (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL,
  device_name  VARCHAR(100),
  platform     VARCHAR(30),
  ip_address   VARCHAR(45),
  last_active  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- AI generated captions cache  
CREATE TABLE IF NOT EXISTS ai_captions (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  caption     TEXT NOT NULL,
  tone        VARCHAR(30) DEFAULT 'casual',
  used        TINYINT(1) DEFAULT 0,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Collab posts (co-authored)
CREATE TABLE IF NOT EXISTS post_collaborators (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  post_id  VARCHAR(36) NOT NULL,
  user_id  VARCHAR(36) NOT NULL,
  accepted TINYINT(1) DEFAULT 0,
  UNIQUE KEY uq_collab (post_id, user_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Add missing columns to existing tables
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_boosted      TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS follower_notifications TINYINT(1) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS show_online_status TINYINT(1) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS show_last_seen  TINYINT(1) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS read_receipts   TINYINT(1) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS verified_at     TIMESTAMP NULL,
  ADD COLUMN IF NOT EXISTS posts_count     INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reels_count     INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS profile_views   INT DEFAULT 0;

ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS is_deleted   TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_boosted   TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS boost_ends_at TIMESTAMP NULL,
  ADD COLUMN IF NOT EXISTS boost_budget DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS allow_comments TINYINT(1) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS saves_count  INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_pinned    TINYINT(1) DEFAULT 0;

ALTER TABLE reels
  ADD COLUMN IF NOT EXISTS is_deleted   TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_pinned    TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS duration     INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS music_title  VARCHAR(200),
  ADD COLUMN IF NOT EXISTS music_artist VARCHAR(200),
  ADD COLUMN IF NOT EXISTS music_url    VARCHAR(600),
  ADD COLUMN IF NOT EXISTS text_overlay TEXT,
  ADD COLUMN IF NOT EXISTS saves_count  INT DEFAULT 0;

ALTER TABLE stories
  ADD COLUMN IF NOT EXISTS text_overlay TEXT,
  ADD COLUMN IF NOT EXISTS bg_color     VARCHAR(20) DEFAULT '#FF6B35',
  ADD COLUMN IF NOT EXISTS music_title  VARCHAR(200),
  ADD COLUMN IF NOT EXISTS music_artist VARCHAR(200),
  ADD COLUMN IF NOT EXISTS music_url    VARCHAR(600),
  ADD COLUMN IF NOT EXISTS font_style   VARCHAR(30) DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS is_close_friends TINYINT(1) DEFAULT 0;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS is_forwarded  TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS forward_count INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS media_thumbnail VARCHAR(600),
  ADD COLUMN IF NOT EXISTS link_preview_url VARCHAR(600),
  ADD COLUMN IF NOT EXISTS link_preview_title VARCHAR(300),
  ADD COLUMN IF NOT EXISTS link_preview_image VARCHAR(600);

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS is_muted    TINYINT(1) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS muted_until TIMESTAMP NULL,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS created_by  VARCHAR(36),
  ADD COLUMN IF NOT EXISTS pinned_message_id VARCHAR(36) NULL;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_posts_user_deleted    ON posts(user_id, is_deleted, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reels_user_deleted    ON reels(user_id, is_deleted, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_user_unread     ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages(conversation_id, is_deleted, created_at);
CREATE INDEX IF NOT EXISTS idx_stories_user_active   ON stories(user_id, is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_follows_status        ON follows(follower_id, following_id, status);
