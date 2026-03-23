# 🔴 RedOrrange — Full-Stack Social Media Platform

A WhatsApp + Instagram hybrid with unique innovations. Built with Flutter + Node.js + MySQL.

---

## 🏗️ Architecture

```
redorrange/
├── frontend/          Flutter cross-platform app (mobile/tablet/web/desktop)
├── backend/           Node.js + Express + Socket.io API
├── database/          MySQL schema (881 lines, 45+ tables)
└── docker-compose.yml One-command setup
```

---

## 🚀 Quick Start

### Prerequisites
- Flutter 3.19+, Dart 3.3+
- Node.js 20+
- MySQL 8+

### Backend

```bash
cd backend
cp .env.example .env   # Fill in your values
npm install
mysql -u root -p < ../database/schema.sql
npm run dev            # Starts on port 3000
```

### Frontend

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_URL=http://YOUR_IP:3000/api \
            --dart-define=WS_URL=http://YOUR_IP:3000
```

### Docker (All-in-one)

```bash
docker-compose up -d   # MySQL + Redis + Node + Nginx
```

---

## 📱 Features

### Messaging (WhatsApp-style)
- Real-time messaging via Socket.io WebSockets
- Voice notes with waveform player
- 8 attachment types: Photo, Video, File, Audio, GIF, Location, Contact, Voice
- Message reactions (8 emoji options)
- Reply, Edit, Delete (for me / for everyone)
- **Orange read ticks** ✓ (sent) ✓✓ (delivered) ✓✓ (seen — orange)
- Typing indicators with animated dots
- Pinned messages
- Starred messages
- Disappearing messages timer
- **Scheduled messages** (send at specific time — unique innovation)
- **Smart AI replies** based on message context
- Message threads

### Social (Instagram-style)
- Feed with infinite scroll
- Stories with text/music overlays
- Highlights
- Reels (TikTok-style vertical video)
- Posts with multi-image carousel
- Reactions (like/love/haha/wow/sad/angry)
- Comments with replies
- Hashtags with explore
- Saved posts

### Calls (WebRTC)
- Audio & video calls
- Camera flip, mute, speaker toggle
- Screen share
- Call history
- Incoming call overlay (works anywhere in the app)

### Unique Innovations (Not in WhatsApp/Instagram)
- 🎯 **Mood system** — set mood with icon and text (auto-expires)
- 📅 **Scheduled messages** — queue messages for future delivery
- 🤖 **Smart replies** — AI-suggested responses
- 📊 **Post insights** — impressions, reach, engagement rate
- 🚀 **Post/Reel boosts** — promote content with budget
- 🎪 **Collaborative posts** — multiple creators on one post
- 📚 **Collections** — save posts into named boards
- 💬 **Mini chat popup** — reply to messages without leaving current page
- 🔔 **In-app call overlay** — full-screen with accept/decline from anywhere
- 🏷️ **Post tags** — tag people in posts (not just in comments)

### Platform Support
- Android 6+ (API 23+)
- iOS 12+
- Web (PWA)
- macOS, Windows, Linux (Flutter desktop)
- Responsive: Mobile → Tablet → Desktop sidebar layout

---

## 🗄️ Database Tables (45+)

| Category | Tables |
|---|---|
| Auth | users, otp_codes, auth_tokens, qr_sessions |
| Social | follows, blocks, contacts, close_friends |
| Content | posts, post_media, likes, comments, shares, saved_posts, hashtags |
| Stories | stories, story_views, story_replies, highlights, highlight_stories |
| Reels | reels, reel_hashtags, reel_saves |
| Messaging | conversations, conversation_members, messages, message_status, message_reactions, pinned_messages, starred_messages, scheduled_messages |
| Calls | calls |
| Events | events, event_attendees |
| Channels | channels, channel_subscriptions, channel_posts |
| Marketplace | marketplace_items, marketplace_saves |
| Live | live_streams, live_comments |
| Settings | user_settings, notification_preferences, push_tokens |
| Analytics | user_analytics, post_boosts |
| Innovations | user_moods, collections, collection_items, post_collaborators, message_threads, ai_suggestions, user_badges, link_previews |

---

## 🔌 API Endpoints (80+)

```
POST /api/auth/send-otp       Send OTP to phone number
POST /api/auth/verify-otp     Verify OTP and log in
GET  /api/auth/qr-generate    Generate QR code for login
GET  /api/auth/qr-status/:id  Check QR login status
GET  /api/users/me            Get current user
PUT  /api/users/profile       Update profile
...
```

---

## 📡 WebSocket Events

**Client → Server:** `join_conversation`, `typing_start`, `typing_stop`, `mark_read`, `message_reaction`, `pin_message`, `star_message`, `call_initiate`, `call_answer`, `call_reject`, `call_end`, `ice_candidate`, `story_viewed`, `join_live`, `leave_live`

**Server → Client:** `new_message`, `user_typing`, `messages_read`, `message_reaction`, `incoming_call`, `call_answered`, `call_rejected`, `call_ended`, `notification`, `user_online`, `live_started`, `live_ended`, `poll_vote`

