-- RedOrrange PostgreSQL Schema
-- Converted from MySQL

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Helper: generate UUID default
-- We use gen_random_uuid() instead of UUID()

-- USERS
CREATE TABLE IF NOT EXISTS users (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  phone_number    VARCHAR(20) UNIQUE NOT NULL,
  country_code    VARCHAR(10) DEFAULT '+1',
  username        VARCHAR(50) UNIQUE,
  display_name    VARCHAR(100),
  bio             TEXT,
  avatar_url      VARCHAR(600),
  cover_url       VARCHAR(600),
  website         VARCHAR(300),
  location        VARCHAR(200),
  gender          VARCHAR(30),
  status_text     VARCHAR(200),
  qr_code         VARCHAR(100),
  last_seen       TIMESTAMP,
  is_online       BOOLEAN DEFAULT FALSE,
  is_verified     BOOLEAN DEFAULT FALSE,
  is_private      BOOLEAN DEFAULT FALSE,
  needs_setup     BOOLEAN DEFAULT TRUE,
  posts_count     INT DEFAULT 0,
  reels_count     INT DEFAULT 0,
  followers_count INT DEFAULT 0,
  following_count INT DEFAULT 0,
  read_receipts        BOOLEAN DEFAULT TRUE,
  show_online_status   BOOLEAN DEFAULT TRUE,
  show_last_seen       BOOLEAN DEFAULT TRUE,
  who_can_message      VARCHAR(20) DEFAULT 'everyone',
  who_can_call         VARCHAR(20) DEFAULT 'everyone',
  who_can_see_stories  VARCHAR(30) DEFAULT 'everyone',
  is_boosted      BOOLEAN DEFAULT FALSE,
  boost_ends_at   TIMESTAMP,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_online ON users(is_online);

-- USER SETTINGS
CREATE TABLE IF NOT EXISTS user_settings (
  id                  SERIAL PRIMARY KEY,
  user_id             VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  two_factor_enabled  BOOLEAN DEFAULT FALSE,
  biometric_enabled   BOOLEAN DEFAULT FALSE,
  login_alerts        BOOLEAN DEFAULT TRUE,
  read_receipts       BOOLEAN DEFAULT TRUE,
  show_online_status  BOOLEAN DEFAULT TRUE,
  show_last_seen      BOOLEAN DEFAULT TRUE,
  who_can_message     VARCHAR(20) DEFAULT 'everyone',
  who_can_call        VARCHAR(20) DEFAULT 'everyone',
  who_can_see_stories VARCHAR(30) DEFAULT 'everyone',
  app_language        VARCHAR(10) DEFAULT 'en',
  theme_mode          VARCHAR(10) DEFAULT 'system',
  auto_download_wifi   JSONB,
  auto_download_mobile JSONB,
  font_size           FLOAT DEFAULT 1.0,
  disappearing_messages INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- NOTIFICATION PREFERENCES
CREATE TABLE IF NOT EXISTS notification_preferences (
  id               SERIAL PRIMARY KEY,
  user_id          VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  messages         BOOLEAN DEFAULT TRUE,
  likes            BOOLEAN DEFAULT TRUE,
  comments         BOOLEAN DEFAULT TRUE,
  follows          BOOLEAN DEFAULT TRUE,
  story_views      BOOLEAN DEFAULT TRUE,
  mentions         BOOLEAN DEFAULT TRUE,
  calls            BOOLEAN DEFAULT TRUE,
  events           BOOLEAN DEFAULT TRUE,
  live             BOOLEAN DEFAULT TRUE,
  marketplace      BOOLEAN DEFAULT FALSE,
  channel_posts    BOOLEAN DEFAULT TRUE,
  email_digest     BOOLEAN DEFAULT FALSE,
  push_enabled     BOOLEAN DEFAULT TRUE,
  quiet_hours_start TIME,
  quiet_hours_end   TIME
);

-- PUSH TOKENS
CREATE TABLE IF NOT EXISTS push_tokens (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      VARCHAR(500) UNIQUE NOT NULL,
  platform   VARCHAR(20) DEFAULT 'android',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id);

-- OTP CODES
CREATE TABLE IF NOT EXISTS otp_codes (
  id           SERIAL PRIMARY KEY,
  phone_number VARCHAR(20) NOT NULL,
  code         VARCHAR(10) NOT NULL,
  is_used      BOOLEAN DEFAULT FALSE,
  verified     BOOLEAN DEFAULT FALSE,
  attempts     INT DEFAULT 0,
  expires_at   TIMESTAMP NOT NULL,
  created_at   TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_otp_phone_time ON otp_codes(phone_number, created_at);

-- AUTH TOKENS
CREATE TABLE IF NOT EXISTS auth_tokens (
  id            SERIAL PRIMARY KEY,
  user_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token         VARCHAR(600),
  refresh_token VARCHAR(600),
  device_info   VARCHAR(300),
  device_name   VARCHAR(300),
  ip_address    VARCHAR(45),
  last_used     TIMESTAMP DEFAULT NOW(),
  expires_at    TIMESTAMP NOT NULL,
  created_at    TIMESTAMP DEFAULT NOW()
);

-- QR SESSIONS
CREATE TABLE IF NOT EXISTS qr_sessions (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id    VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
  qr_token   VARCHAR(100),
  status     VARCHAR(20) DEFAULT 'pending',
  scanned_by VARCHAR(36),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- FOLLOWS
CREATE TABLE IF NOT EXISTS follows (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  follower_id  VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       VARCHAR(20) DEFAULT 'accepted',
  created_at   TIMESTAMP DEFAULT NOW(),
  UNIQUE(follower_id, following_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- BLOCKS
CREATE TABLE IF NOT EXISTS blocks (
  id         SERIAL PRIMARY KEY,
  blocker_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_id)
);

-- CONTACTS
CREATE TABLE IF NOT EXISTS contacts (
  id           SERIAL PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_id   VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  nickname     VARCHAR(100),
  is_favorite  BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, contact_id)
);

-- CLOSE FRIENDS
CREATE TABLE IF NOT EXISTS close_friends (
  id          SERIAL PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id   VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_at    TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, friend_id)
);

-- POSTS
CREATE TABLE IF NOT EXISTS posts (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id         VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  caption         TEXT,
  location        VARCHAR(200),
  type            VARCHAR(20) DEFAULT 'image',
  is_public       BOOLEAN DEFAULT TRUE,
  allow_comments  BOOLEAN DEFAULT TRUE,
  allow_sharing   BOOLEAN DEFAULT TRUE,
  is_boosted      BOOLEAN DEFAULT FALSE,
  boost_budget    DECIMAL(10,2) DEFAULT 0,
  boost_ends_at   TIMESTAMP,
  is_deleted      BOOLEAN DEFAULT FALSE,
  likes_count     INT DEFAULT 0,
  comments_count  INT DEFAULT 0,
  shares_count    INT DEFAULT 0,
  views_count     INT DEFAULT 0,
  saves_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_posts_user_created ON posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_public ON posts(is_public, is_deleted, created_at DESC);

-- POST MEDIA
CREATE TABLE IF NOT EXISTS post_media (
  id            VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id       VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  media_url     VARCHAR(600) NOT NULL,
  media_type    VARCHAR(20) DEFAULT 'image',
  thumbnail_url VARCHAR(600),
  width         INT,
  height        INT,
  duration      INT,
  file_size     INT,
  order_index   INT DEFAULT 0
);

-- LIKES
CREATE TABLE IF NOT EXISTS likes (
  id             VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type    VARCHAR(20) NOT NULL,
  target_id      VARCHAR(36) NOT NULL,
  reaction_type  VARCHAR(20) DEFAULT 'like',
  created_at     TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_likes_target ON likes(target_type, target_id);

-- COMMENTS
CREATE TABLE IF NOT EXISTS comments (
  id            VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type   VARCHAR(20) NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  parent_id     VARCHAR(36),
  content       TEXT NOT NULL,
  is_deleted    BOOLEAN DEFAULT FALSE,
  likes_count   INT DEFAULT 0,
  replies_count INT DEFAULT 0,
  created_at    TIMESTAMP DEFAULT NOW(),
  updated_at    TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comments_target ON comments(target_type, target_id);

-- SHARES
CREATE TABLE IF NOT EXISTS shares (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id    VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, post_id)
);

-- SAVED POSTS
CREATE TABLE IF NOT EXISTS saved_posts (
  id            SERIAL PRIMARY KEY,
  user_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id       VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  collection    VARCHAR(100) DEFAULT 'All Posts',
  saved_at      TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, post_id)
);

-- HASHTAGS
CREATE TABLE IF NOT EXISTS hashtags (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name        VARCHAR(100) UNIQUE NOT NULL,
  posts_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS post_hashtags (
  post_id     VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  hashtag_id  VARCHAR(36) NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, hashtag_id)
);

-- STORIES
CREATE TABLE IF NOT EXISTS stories (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id      VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  media_url    VARCHAR(600),
  media_type   VARCHAR(20) DEFAULT 'image',
  caption      VARCHAR(500),
  text_overlay TEXT,
  bg_color     VARCHAR(20) DEFAULT '#FF6B35',
  music_title  VARCHAR(200),
  music_artist VARCHAR(200),
  music_url    VARCHAR(600),
  duration     INT DEFAULT 5,
  views_count  INT DEFAULT 0,
  type         VARCHAR(20) DEFAULT 'public',
  expires_at   TIMESTAMP NOT NULL,
  created_at   TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stories_user_expires ON stories(user_id, expires_at);

CREATE TABLE IF NOT EXISTS story_views (
  id         SERIAL PRIMARY KEY,
  story_id   VARCHAR(36) NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  viewer_id  VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  viewed_at  TIMESTAMP DEFAULT NOW(),
  UNIQUE(story_id, viewer_id)
);

CREATE TABLE IF NOT EXISTS story_replies (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  story_id   VARCHAR(36) NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  sender_id  VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- HIGHLIGHTS
CREATE TABLE IF NOT EXISTS highlights (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      VARCHAR(100) NOT NULL,
  cover_url  VARCHAR(600),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS highlight_stories (
  highlight_id VARCHAR(36) NOT NULL REFERENCES highlights(id) ON DELETE CASCADE,
  story_id     VARCHAR(36) NOT NULL,
  order_index  INT DEFAULT 0,
  PRIMARY KEY (highlight_id, story_id)
);

-- REELS
CREATE TABLE IF NOT EXISTS reels (
  id             VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_url      VARCHAR(600) NOT NULL,
  thumbnail_url  VARCHAR(600),
  caption        TEXT,
  music_title    VARCHAR(200),
  music_artist   VARCHAR(200),
  music_url      VARCHAR(600),
  text_overlay   TEXT,
  duration       INT,
  views_count    INT DEFAULT 0,
  likes_count    INT DEFAULT 0,
  comments_count INT DEFAULT 0,
  shares_count   INT DEFAULT 0,
  saves_count    INT DEFAULT 0,
  is_deleted     BOOLEAN DEFAULT FALSE,
  created_at     TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reel_hashtags (
  reel_id    VARCHAR(36) NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
  hashtag_id VARCHAR(36) NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY (reel_id, hashtag_id)
);

CREATE TABLE IF NOT EXISTS reel_saves (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  reel_id    VARCHAR(36) NOT NULL,
  saved_at   TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, reel_id)
);

-- CONVERSATIONS & MESSAGES
CREATE TABLE IF NOT EXISTS conversations (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  type            VARCHAR(20) DEFAULT 'direct',
  name            VARCHAR(200),
  description     TEXT,
  avatar_url      VARCHAR(600),
  created_by      VARCHAR(36),
  last_message_id VARCHAR(36),
  last_message_at TIMESTAMP DEFAULT NOW(),
  is_announcement BOOLEAN DEFAULT FALSE,
  disappearing_timer INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_members (
  id                   SERIAL PRIMARY KEY,
  conversation_id      VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id              VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role                 VARCHAR(20) DEFAULT 'member',
  last_read_message_id VARCHAR(36),
  muted_until          TIMESTAMP,
  is_archived          BOOLEAN DEFAULT FALSE,
  is_pinned            BOOLEAN DEFAULT FALSE,
  disappearing_timer   INT DEFAULT 0,
  joined_at            TIMESTAMP DEFAULT NOW(),
  left_at              TIMESTAMP,
  UNIQUE(conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_conv_members_user ON conversation_members(user_id);

CREATE TABLE IF NOT EXISTS messages (
  id                VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  conversation_id   VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id         VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type              VARCHAR(30) DEFAULT 'text',
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
  is_forwarded      BOOLEAN DEFAULT FALSE,
  is_edited         BOOLEAN DEFAULT FALSE,
  is_deleted        BOOLEAN DEFAULT FALSE,
  deleted_for_all   BOOLEAN DEFAULT FALSE,
  expires_at        TIMESTAMP,
  created_at        TIMESTAMP DEFAULT NOW(),
  updated_at        TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages(conversation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS message_status (
  id         SERIAL PRIMARY KEY,
  message_id VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id    VARCHAR(36) NOT NULL,
  status     VARCHAR(20) DEFAULT 'delivered',
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(message_id, user_id)
);

CREATE TABLE IF NOT EXISTS message_reactions (
  id         SERIAL PRIMARY KEY,
  message_id VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji      VARCHAR(10) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(message_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS pinned_messages (
  id              SERIAL PRIMARY KEY,
  conversation_id VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  message_id      VARCHAR(36) NOT NULL,
  pinned_by       VARCHAR(36) NOT NULL,
  pinned_at       TIMESTAMP DEFAULT NOW(),
  UNIQUE(conversation_id, message_id)
);

CREATE TABLE IF NOT EXISTS starred_messages (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message_id VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  starred_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, message_id)
);

-- SCHEDULED MESSAGES
CREATE TABLE IF NOT EXISTS scheduled_messages (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  conversation_id VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type            VARCHAR(20) DEFAULT 'text',
  content         TEXT,
  media_url       VARCHAR(600),
  scheduled_at    TIMESTAMP NOT NULL,
  status          VARCHAR(20) DEFAULT 'pending',
  created_at      TIMESTAMP DEFAULT NOW()
);

-- CALLS
CREATE TABLE IF NOT EXISTS calls (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  caller_id   VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  callee_id   VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        VARCHAR(10) NOT NULL,
  status      VARCHAR(20) DEFAULT 'calling',
  duration    INT DEFAULT 0,
  started_at  TIMESTAMP,
  ended_at    TIMESTAMP,
  created_at  TIMESTAMP DEFAULT NOW()
);

-- EVENTS
CREATE TABLE IF NOT EXISTS events (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  creator_id      VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  cover_url       VARCHAR(600),
  event_type      VARCHAR(20) DEFAULT 'public',
  start_datetime  TIMESTAMP NOT NULL,
  end_datetime    TIMESTAMP,
  location        VARCHAR(300),
  online_link     VARCHAR(500),
  going_count     INT DEFAULT 0,
  interested_count INT DEFAULT 0,
  views_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS event_attendees (
  id         SERIAL PRIMARY KEY,
  event_id   VARCHAR(36) NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status     VARCHAR(20) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(event_id, user_id)
);

-- NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id     VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id    VARCHAR(36),
  type        VARCHAR(50) NOT NULL,
  target_type VARCHAR(50),
  target_id   VARCHAR(36),
  message     TEXT,
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read, created_at DESC);

-- SEARCH HISTORY
CREATE TABLE IF NOT EXISTS search_history (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  query      VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- REPORTS
CREATE TABLE IF NOT EXISTS reports (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  reporter_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type VARCHAR(30) NOT NULL,
  target_id   VARCHAR(36) NOT NULL,
  reason      VARCHAR(200) NOT NULL,
  details     TEXT,
  status      VARCHAR(20) DEFAULT 'pending',
  created_at  TIMESTAMP DEFAULT NOW()
);

-- MARKETPLACE
CREATE TABLE IF NOT EXISTS marketplace_items (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  seller_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title           VARCHAR(255) NOT NULL,
  description     TEXT,
  price           DECIMAL(14,2),
  currency        VARCHAR(5) DEFAULT 'USD',
  category        VARCHAR(80),
  condition_type  VARCHAR(20) DEFAULT 'used',
  location        VARCHAR(255),
  images          JSONB,
  status          VARCHAR(20) DEFAULT 'active',
  views_count     INT DEFAULT 0,
  saves_count     INT DEFAULT 0,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS marketplace_saves (
  id       SERIAL PRIMARY KEY,
  user_id  VARCHAR(36) NOT NULL,
  item_id  VARCHAR(36) NOT NULL,
  saved_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, item_id)
);

-- CHANNELS
CREATE TABLE IF NOT EXISTS channels (
  id                VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  owner_id          VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name              VARCHAR(150) NOT NULL,
  description       TEXT,
  avatar_url        VARCHAR(600),
  cover_url         VARCHAR(600),
  category          VARCHAR(50),
  is_verified       BOOLEAN DEFAULT FALSE,
  subscribers_count INT DEFAULT 0,
  posts_count       INT DEFAULT 0,
  created_at        TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS channel_subscriptions (
  id            SERIAL PRIMARY KEY,
  channel_id    VARCHAR(36) NOT NULL,
  user_id       VARCHAR(36) NOT NULL,
  subscribed_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(channel_id, user_id)
);

CREATE TABLE IF NOT EXISTS channel_posts (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  channel_id  VARCHAR(36) NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  content     TEXT,
  media_url   VARCHAR(600),
  media_type  VARCHAR(20) DEFAULT 'text',
  views_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT NOW()
);

-- LIVE STREAMS
CREATE TABLE IF NOT EXISTS live_streams (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id      VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title        VARCHAR(255),
  stream_key   VARCHAR(100) UNIQUE,
  status       VARCHAR(20) DEFAULT 'live',
  viewer_count INT DEFAULT 0,
  peak_viewers INT DEFAULT 0,
  started_at   TIMESTAMP,
  ended_at     TIMESTAMP,
  created_at   TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS live_comments (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  stream_id  VARCHAR(36) NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content    VARCHAR(500) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- POLLS
CREATE TABLE IF NOT EXISTS polls (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id    VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  question   TEXT NOT NULL,
  expires_at TIMESTAMP,
  multiple   BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS poll_options (
  id         SERIAL PRIMARY KEY,
  poll_id    VARCHAR(36) NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
  text       VARCHAR(255) NOT NULL,
  votes      INT DEFAULT 0,
  order_idx  INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS poll_votes (
  id         SERIAL PRIMARY KEY,
  poll_id    VARCHAR(36) NOT NULL,
  option_id  INT NOT NULL,
  user_id    VARCHAR(36) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(poll_id, user_id, option_id)
);

-- USER ANALYTICS
CREATE TABLE IF NOT EXISTS user_analytics (
  id               SERIAL PRIMARY KEY,
  user_id          VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date             DATE NOT NULL,
  profile_views    INT DEFAULT 0,
  post_impressions INT DEFAULT 0,
  story_views      INT DEFAULT 0,
  reel_views       INT DEFAULT 0,
  link_clicks      INT DEFAULT 0,
  new_followers    INT DEFAULT 0,
  UNIQUE(user_id, date)
);

-- MOODS
CREATE TABLE IF NOT EXISTS user_moods (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mood_type  VARCHAR(50),
  mood_text  VARCHAR(200),
  mood_icon  VARCHAR(10),
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- POST COLLABORATORS
CREATE TABLE IF NOT EXISTS post_collaborators (
  id       SERIAL PRIMARY KEY,
  post_id  VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id  VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status   VARCHAR(20) DEFAULT 'pending',
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

-- COLLECTIONS
CREATE TABLE IF NOT EXISTS collections (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id     VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        VARCHAR(100) NOT NULL,
  cover_url   VARCHAR(600),
  is_private  BOOLEAN DEFAULT FALSE,
  items_count INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS collection_items (
  id            SERIAL PRIMARY KEY,
  collection_id VARCHAR(36) NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  target_type   VARCHAR(20) NOT NULL,
  target_id     VARCHAR(36) NOT NULL,
  added_at      TIMESTAMP DEFAULT NOW(),
  UNIQUE(collection_id, target_type, target_id)
);

-- MESSAGE THREADS
CREATE TABLE IF NOT EXISTS message_threads (
  id               VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  parent_message_id VARCHAR(36) NOT NULL,
  conversation_id  VARCHAR(36) NOT NULL,
  replies_count    INT DEFAULT 0,
  last_reply_at    TIMESTAMP DEFAULT NOW(),
  UNIQUE(parent_message_id)
);

-- AI SUGGESTIONS
CREATE TABLE IF NOT EXISTS ai_suggestions (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id     VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  context     TEXT,
  suggestions JSONB,
  created_at  TIMESTAMP DEFAULT NOW()
);

-- USER BADGES
CREATE TABLE IF NOT EXISTS user_badges (
  id         SERIAL PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_type VARCHAR(50) NOT NULL,
  awarded_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, badge_type)
);

-- LINK PREVIEWS
CREATE TABLE IF NOT EXISTS link_previews (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  url         TEXT NOT NULL,
  title       VARCHAR(500),
  description TEXT,
  image_url   VARCHAR(600),
  favicon_url VARCHAR(600),
  created_at  TIMESTAMP DEFAULT NOW()
);

-- POST BOOSTS
CREATE TABLE IF NOT EXISTS post_boosts (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  post_id    VARCHAR(36) NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  budget     DECIMAL(10,2) NOT NULL,
  spent      DECIMAL(10,2) DEFAULT 0,
  impressions INT DEFAULT 0,
  clicks     INT DEFAULT 0,
  status     VARCHAR(20) DEFAULT 'active',
  starts_at  TIMESTAMP DEFAULT NOW(),
  ends_at    TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- GROUPS (alias for group conversations)
CREATE TABLE IF NOT EXISTS groups (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name        VARCHAR(200) NOT NULL,
  description TEXT,
  avatar_url  VARCHAR(600),
  created_by  VARCHAR(36) REFERENCES users(id),
  conversation_id VARCHAR(36),
  created_at  TIMESTAMP DEFAULT NOW()
);

-- COIN PACKAGES
CREATE TABLE IF NOT EXISTS coin_packages (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name         VARCHAR(100) NOT NULL,
  coins        INT NOT NULL,
  price_usd    DECIMAL(10,2) NOT NULL,
  price_rwf    DECIMAL(10,2),
  bonus_coins  INT DEFAULT 0,
  is_popular   BOOLEAN DEFAULT FALSE,
  is_active    BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMP DEFAULT NOW()
);

-- USER WALLETS
CREATE TABLE IF NOT EXISTS user_wallets (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id      VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  coins        INT DEFAULT 0,
  locked_coins INT DEFAULT 0,
  total_earned DECIMAL(14,2) DEFAULT 0,
  total_spent  DECIMAL(14,2) DEFAULT 0,
  created_at   TIMESTAMP DEFAULT NOW(),
  updated_at   TIMESTAMP DEFAULT NOW()
);

-- COIN TRANSACTIONS
CREATE TABLE IF NOT EXISTS coin_transactions (
  id             VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type           VARCHAR(30) NOT NULL,
  amount         INT NOT NULL,
  balance_before INT NOT NULL,
  balance_after  INT NOT NULL,
  reference_id   VARCHAR(36),
  reference_type VARCHAR(30) DEFAULT 'purchase',
  description    VARCHAR(255),
  metadata       JSONB,
  created_at     TIMESTAMP DEFAULT NOW()
);

-- GIFTS
CREATE TABLE IF NOT EXISTS gifts (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name        VARCHAR(100) NOT NULL,
  emoji       VARCHAR(10) NOT NULL,
  icon_url    VARCHAR(600),
  coin_price  INT NOT NULL,
  category    VARCHAR(20) DEFAULT 'basic',
  effect      VARCHAR(50),
  is_active   BOOLEAN DEFAULT TRUE,
  sort_order  INT DEFAULT 0,
  created_at  TIMESTAMP DEFAULT NOW()
);

-- GIFT TRANSACTIONS
CREATE TABLE IF NOT EXISTS gift_transactions (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  sender_id    VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id  VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gift_id      VARCHAR(36) NOT NULL REFERENCES gifts(id),
  quantity     INT DEFAULT 1,
  coins_spent  INT NOT NULL,
  context_type VARCHAR(20) DEFAULT 'live',
  context_id   VARCHAR(36),
  message      VARCHAR(200),
  created_at   TIMESTAMP DEFAULT NOW()
);

-- PAYMENT ORDERS
CREATE TABLE IF NOT EXISTS payment_orders (
  id             VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  package_id     VARCHAR(36) NOT NULL,
  amount_usd     DECIMAL(10,2) NOT NULL,
  amount_local   DECIMAL(10,2),
  currency       VARCHAR(5) DEFAULT 'USD',
  coins          INT NOT NULL,
  bonus_coins    INT DEFAULT 0,
  status         VARCHAR(20) DEFAULT 'pending',
  payment_method VARCHAR(30) NOT NULL,
  provider_ref   VARCHAR(200),
  provider_data  JSONB,
  failure_reason VARCHAR(300),
  completed_at   TIMESTAMP,
  created_at     TIMESTAMP DEFAULT NOW()
);

-- ESCROW ORDERS
CREATE TABLE IF NOT EXISTS escrow_orders (
  id              VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  buyer_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seller_id       VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  item_id         VARCHAR(36) NOT NULL REFERENCES marketplace_items(id),
  amount_usd      DECIMAL(14,2) NOT NULL,
  platform_fee    DECIMAL(14,2) NOT NULL,
  seller_receives DECIMAL(14,2) NOT NULL,
  status          VARCHAR(30) DEFAULT 'pending',
  payment_method  VARCHAR(50),
  payment_ref     VARCHAR(200),
  tracking_number VARCHAR(200),
  buyer_confirmed BOOLEAN DEFAULT FALSE,
  seller_confirmed BOOLEAN DEFAULT FALSE,
  dispute_reason  TEXT,
  dispute_opened_at TIMESTAMP,
  dispute_resolved_at TIMESTAMP,
  auto_release_at TIMESTAMP,
  funded_at       TIMESTAMP,
  completed_at    TIMESTAMP,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW()
);

-- ESCROW EVENTS LOG
CREATE TABLE IF NOT EXISTS escrow_events (
  id         VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  order_id   VARCHAR(36) NOT NULL REFERENCES escrow_orders(id) ON DELETE CASCADE,
  actor_id   VARCHAR(36),
  event_type VARCHAR(30) NOT NULL,
  details    TEXT,
  metadata   JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- CREATOR PAYOUTS
CREATE TABLE IF NOT EXISTS creator_payouts (
  id             VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id        VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_usd     DECIMAL(10,2) NOT NULL,
  coins_redeemed INT NOT NULL,
  payout_method  VARCHAR(30) NOT NULL,
  account_details JSONB,
  status         VARCHAR(20) DEFAULT 'pending',
  provider_ref   VARCHAR(200),
  created_at     TIMESTAMP DEFAULT NOW(),
  processed_at   TIMESTAMP
);

-- SUBSCRIPTION PLANS
CREATE TABLE IF NOT EXISTS subscription_plans (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name         VARCHAR(100) NOT NULL,
  price_usd    DECIMAL(10,2) NOT NULL,
  price_rwf    DECIMAL(10,2),
  duration_days INT NOT NULL,
  features     JSONB,
  is_active    BOOLEAN DEFAULT TRUE
);

-- USER SUBSCRIPTIONS
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id          VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id     VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id     VARCHAR(36) NOT NULL REFERENCES subscription_plans(id),
  status      VARCHAR(20) DEFAULT 'active',
  started_at  TIMESTAMP DEFAULT NOW(),
  expires_at  TIMESTAMP NOT NULL,
  auto_renew  BOOLEAN DEFAULT TRUE
);

-- AUDIT LOGS
CREATE TABLE IF NOT EXISTS audit_logs (
  id         BIGSERIAL PRIMARY KEY,
  user_id    VARCHAR(36),
  action     VARCHAR(100) NOT NULL,
  resource   VARCHAR(100),
  resource_id VARCHAR(36),
  ip_address VARCHAR(45),
  user_agent VARCHAR(300),
  metadata   JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ADS
CREATE TABLE IF NOT EXISTS ads (
  id           VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
  advertiser_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title        VARCHAR(255) NOT NULL,
  description  TEXT,
  media_url    VARCHAR(600),
  media_type   VARCHAR(20) DEFAULT 'image',
  cta_text     VARCHAR(100),
  cta_url      VARCHAR(500),
  target_gender VARCHAR(20),
  target_age_min INT,
  target_age_max INT,
  target_interests JSONB,
  budget       DECIMAL(10,2) NOT NULL,
  spent        DECIMAL(10,2) DEFAULT 0,
  impressions  INT DEFAULT 0,
  clicks       INT DEFAULT 0,
  conversions  INT DEFAULT 0,
  status       VARCHAR(20) DEFAULT 'pending',
  starts_at    TIMESTAMP,
  ends_at      TIMESTAMP,
  created_at   TIMESTAMP DEFAULT NOW()
);

-- Insert seed data
INSERT INTO coin_packages (id, name, coins, price_usd, price_rwf, bonus_coins, is_popular) VALUES
  ('cp-1','Starter Pack', 100, 0.99, 1200, 0, FALSE),
  ('cp-2','Basic Pack',   500, 4.99, 5900, 50, FALSE),
  ('cp-3','Popular Pack', 1200, 9.99, 11900, 200, TRUE),
  ('cp-4','Value Pack',   2500, 19.99, 23900, 500, FALSE),
  ('cp-5','Pro Pack',     6500, 49.99, 59900, 1500, FALSE),
  ('cp-6','Elite Pack',   14000, 99.99, 119900, 4000, FALSE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO gifts (id, name, emoji, coin_price, category, sort_order) VALUES
  ('g-1', 'Heart',       E'\u2764\ufe0f',  10,  'basic',   1),
  ('g-2', 'Rose',        E'\U0001f339',  50,  'basic',   2),
  ('g-3', 'Fire',        E'\U0001f525',  30,  'basic',   3),
  ('g-4', 'Star',        E'\u2b50',  80,  'basic',   4),
  ('g-5', 'Crown',       E'\U0001f451',  200, 'premium', 5),
  ('g-6', 'Diamond',     E'\U0001f48e',  500, 'premium', 6),
  ('g-7', 'Rocket',      E'\U0001f680',  150, 'premium', 7),
  ('g-8', 'Trophy',      E'\U0001f3c6',  300, 'premium', 8),
  ('g-9', 'Lion',        E'\U0001f981',  800, 'special', 9),
  ('g-10','Universe',    E'\U0001f30c', 1000, 'special', 10),
  ('g-11','Supernova',   E'\U0001f4a5', 2000, 'special', 11),
  ('g-12','Luxury Car',  E'\U0001f3ce\ufe0f', 5000, 'special', 12)
ON CONFLICT (id) DO NOTHING;

INSERT INTO subscription_plans (id, name, price_usd, price_rwf, duration_days, features) VALUES
  ('sp-1', 'RedOrrange Plus',  4.99, 5900, 30, '["No ads","Verified badge","500 monthly coins","Priority support","Exclusive stickers"]'),
  ('sp-2', 'RedOrrange Pro',   9.99, 11900, 30, '["Everything in Plus","2000 monthly coins","Analytics Pro","Custom themes","Creator tools","Revenue sharing"]'),
  ('sp-3', 'RedOrrange Elite', 29.99, 35900, 30, '["Everything in Pro","5000 monthly coins","White glove support","Early features","Creator fund eligible","Promoted content"]')
ON CONFLICT (id) DO NOTHING;
