# RedOrrange - Social Media Platform

## Overview
RedOrrange is a full-stack social media platform combining WhatsApp-style messaging with Instagram-style content sharing. It includes features like scheduled messages, a mood system, smart AI replies, and custom read receipts ("orange ticks").

## Architecture
- **Backend**: Node.js + Express + Socket.io, runs on port 5000
- **Database**: PostgreSQL (Replit built-in), schema in `database/pg_schema.sql`
- **Frontend**: Flutter (cross-platform mobile/web/desktop)

## Key Features
- Real-time messaging via WebSockets (Socket.io)
- Stories, Reels, Posts
- Group chats and channels
- Scheduled messages (node-cron)
- Marketplace, polls, events
- Payment integrations (Stripe, PayPal, Flutterwave)
- No Firebase — fully self-contained real-time system

## Running the Project
The backend starts automatically via the "Start application" workflow:
```
cd backend && node server.js
```

Health check: `GET /health`

## Environment Variables
- `PORT=5000` — server port
- `NODE_ENV=development`
- `JWT_SECRET` — JWT signing key
- `DATABASE_URL` — PostgreSQL connection (Replit-managed)

## Database
PostgreSQL schema is in `database/pg_schema.sql`. Applied once during migration.
The database config is in `backend/src/config/database.js` using the `pg` pool with `DATABASE_URL`.

## API Routes
All routes are prefixed with `/api/`:
- `/api/auth` - Authentication
- `/api/users` - User profiles
- `/api/messages` - Messaging
- `/api/posts`, `/api/stories`, `/api/reels` - Content
- `/api/groups`, `/api/channels` - Group features
- `/api/marketplace`, `/api/payments` - Commerce
- `/api/admin` - Administration
