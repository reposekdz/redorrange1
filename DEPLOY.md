# RedOrrange Deployment Guide

## 🔌 Messaging Architecture (No Firebase)

All real-time communication uses **Socket.io WebSockets only**:

```
Flutter App ←→ Socket.io (WebSocket) ←→ Node.js Server ←→ MySQL
```

- Messages, calls, notifications, live events: all via WebSocket
- Offline notifications: stored in DB, delivered on reconnect
- Local system notifications: `flutter_local_notifications` (Android/iOS/macOS/Linux)
- Web notifications: Browser Notification API (no FCM)

---

## 🚀 Backend Deployment

### Environment Variables
```env
PORT=3000
DB_HOST=localhost
DB_PORT=3306
DB_USER=redorrange
DB_PASSWORD=YOUR_STRONG_PASSWORD
DB_NAME=redorrange
JWT_SECRET=YOUR_64_CHAR_RANDOM_SECRET
JWT_REFRESH_SECRET=ANOTHER_64_CHAR_RANDOM_SECRET
NODE_ENV=production
UPLOAD_BASE_URL=https://api.redorrange.app/uploads
```

### Docker (Recommended)
```bash
# Setup
cp backend/.env.example backend/.env
# Edit .env with your values

# Start all services
docker-compose up -d

# Check logs
docker-compose logs -f api
```

### Manual
```bash
cd backend
npm ci --production
mysql -u root -p < ../database/schema.sql
NODE_ENV=production node server.js
```

### Nginx Proxy (Production)
```nginx
server {
  listen 443 ssl;
  server_name api.redorrange.app;
  ssl_certificate     /etc/letsencrypt/live/api.redorrange.app/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/api.redorrange.app/privkey.pem;

  location / {
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";  # Critical for WebSocket!
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;  # Keep WS alive
    proxy_send_timeout 86400;
  }
}
```

---

## 📱 Android Build

```bash
cd frontend

# Debug (development)
flutter run --dart-define=API_URL=http://YOUR_IP:3000/api \
            --dart-define=WS_URL=http://YOUR_IP:3000

# Release APK
flutter build apk --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app

# Release AAB (Play Store)
flutter build appbundle --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app
```

### Android Signing (Release)
```bash
keytool -genkey -v -keystore ~/redorrange-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias redorrange
```

Add to `android/key.properties`:
```
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=redorrange
storeFile=/path/to/redorrange-release.jks
```

---

## 🍎 iOS Build

```bash
cd frontend
flutter build ios --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app

# Open in Xcode for App Store submission
open ios/Runner.xcworkspace
```

### iOS Requirements
- macOS with Xcode 15+
- Apple Developer Account ($99/year)
- Set Bundle ID: `com.redorrange.app`
- Enable capabilities: Push Notifications, Background Modes

---

## 🌐 Web Build

```bash
cd frontend

# Build
flutter build web --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app \
  --web-renderer=canvaskit

# Deploy to any static host
rsync -av build/web/ user@server:/var/www/redorrange/
```

### Nginx Web Config
```nginx
server {
  listen 443 ssl;
  server_name redorrange.app;
  root /var/www/redorrange;
  index index.html;

  # Flutter PWA — serve all routes as index.html
  location / { try_files $uri $uri/ /index.html; }

  # Cache static assets
  location ~* \.(js|css|png|jpg|ico|wasm)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
}
```

---

## 🖥️ Desktop Builds

```bash
# macOS
flutter build macos --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app

# Windows
flutter build windows --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app

# Linux
flutter build linux --release \
  --dart-define=API_URL=https://api.redorrange.app/api \
  --dart-define=WS_URL=wss://api.redorrange.app
```

---

## 🗄️ Database Setup

```bash
mysql -u root -p
CREATE DATABASE redorrange CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'redorrange'@'localhost' IDENTIFIED BY 'YOUR_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON redorrange.* TO 'redorrange'@'localhost';
FLUSH PRIVILEGES;

# Import schema
mysql -u redorrange -p redorrange < database/schema.sql
```

### MySQL Production Config (`/etc/mysql/mysql.conf.d/mysqld.cnf`)
```ini
[mysqld]
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
max_connections      = 200
innodb_buffer_pool_size = 1G
slow_query_log       = 1
long_query_time      = 2
```

---

## 🔒 Security Checklist

- [ ] Change all default passwords in `.env`
- [ ] Use HTTPS/WSS in production (not HTTP/WS)
- [ ] Set `NODE_ENV=production`
- [ ] Enable MySQL user with limited permissions
- [ ] Set up rate limiting (already in code)
- [ ] Configure firewall: only ports 80, 443, 22 open
- [ ] Regular database backups
- [ ] Monitor with PM2 or systemd

### PM2 Process Manager
```bash
npm install -g pm2
cd backend
pm2 start server.js --name redorrange-api --instances 2
pm2 startup
pm2 save
```

---

## 📊 WebSocket Connection Check

Test your WebSocket connection:
```javascript
// Browser console
const ws = new WebSocket('wss://api.redorrange.app');
ws.onopen = () => console.log('WebSocket connected ✅');
ws.onerror = (e) => console.error('WebSocket error:', e);
```

---

## 🌍 Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| Android 6+ (API 23+) | ✅ | APK + AAB |
| iOS 12+ | ✅ | Requires macOS + Xcode |
| Web (Chrome/Firefox/Safari) | ✅ | PWA installable |
| macOS 10.14+ | ✅ | Requires Flutter macOS |
| Windows 10+ | ✅ | Requires Flutter Windows |
| Linux (Ubuntu 18+) | ✅ | Requires Flutter Linux |

