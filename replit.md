# RedOrrange - Social Media Platform

## Overview
RedOrrange is a full-stack social media platform combining WhatsApp-style messaging with Instagram-style content sharing. Real OTP auth, QR code login, real-time messaging with reactions/receipts, stories, reels, posts, notifications, live streaming, marketplace, events, wallet, and more.

## Architecture
- **Backend**: Node.js + Express + Socket.io, runs on port 5000
- **Database**: PostgreSQL (Replit built-in), schema in `database/pg_schema.sql`
- **Frontend**: Flutter 3.32.0 compiled to web, served from `frontend/web/`

## Key Features
- Real-time messaging via Socket.io (no Firebase)
- OTP auth (dev mode shows code hint) + QR code login
- Stories, Reels, Posts with likes/comments/reactions
- Group chats, channels, voice/video calls (WebRTC)
- Scheduled messages, disappearing messages, starred messages
- Marketplace, polls, events, live streaming
- Notifications, push (browser API on web)
- Wallet, subscriptions, gifts, Stripe payments
- Responsive split-layout auth (welcome panel left, form right on wide screens)
- Sidebar navigation on desktop, bottom bar on mobile

## Running the Project
Backend starts via the "Start application" workflow:
```
cd backend && node server.js
```
Flutter web is pre-built and served from `frontend/web/`.

## Rebuilding Flutter Web
After editing Dart files:
```bash
cd frontend && flutter build web --release --no-tree-shake-icons
cp -r frontend/build/web/. frontend/web/
```

## Important Files
- `backend/server.js` — 80+ REST endpoints + Socket.io events
- `frontend/lib/core/services/api_service.dart` — HTTP client, auto-detects web URL from `Uri.base`
- `frontend/lib/core/services/socket_service.dart` — WebSocket client, auto-detects web URL from `Uri.base`
- `frontend/lib/core/router/app_router.dart` — All app routes
- `frontend/lib/main.dart` — App entry point

## Web URL Detection
On web (`kIsWeb == true`), both the API service and socket service derive their base URL from `Uri.base` (the current page URL), so they always connect to the correct Replit server regardless of domain.

## Environment Variables
- `PORT=5000` — server port
- `NODE_ENV=development`
- `DATABASE_URL` — PostgreSQL connection (Replit auto-provides)
- `JWT_SECRET` — token signing
- `STRIPE_PUBLISHABLE_KEY` — passed via `--dart-define` at build time (optional)

## Auth Flow
1. User enters phone → backend returns OTP (dev_code shown in dev mode)
2. User enters 6-digit code → JWT issued → redirected to SetupScreen (new) or HomeScreen (existing)
3. OR: QR login — generate QR → scan from other device → approved via socket event

## Database
All tables created from `database/pg_schema.sql`. Uses PostgreSQL with parameterized queries (`$1, $2...`).
