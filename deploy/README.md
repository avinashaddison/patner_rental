# Production Deployment — Companion Ranchi

End-to-end guide to take **Companion Ranchi** to production: a non-adult companionship
marketplace (Ranchi, India). It covers the backend (Node.js/Express + Prisma + Socket.IO),
the admin panel (Next.js), the PostgreSQL database, and the Flutter release build, plus every
third-party integration (Razorpay, Cloudflare R2, Firebase FCM, MSG91 SMS OTP).

> **Policy reminder — enforced in code, not just docs.** This platform is **companionship /
> social-activity only** (coffee, movies, shopping, events, city tours, networking,
> conversation). It is **not** an escort or adult-services platform. Meetings are restricted
> to **public places only** and all users must be verified adults (**18+**). Keep these rules
> intact across every environment. See [docs/SAFETY.md](../docs/SAFETY.md) and the
> [production checklist](./production-checklist.md).

## Contents

1. [Architecture recap](#1-architecture-recap)
2. [Prerequisites](#2-prerequisites)
3. [Provision PostgreSQL](#3-provision-postgresql)
4. [Environment variables](#4-environment-variables)
5. [Database: migrate + seed](#5-database-migrate--seed)
6. [Deploy the backend](#6-deploy-the-backend)
   - [Option A — Docker / docker-compose](#option-a--docker--docker-compose)
   - [Option B — Render](#option-b--render)
   - [Option C — Railway](#option-c--railway)
   - [Option D — VPS + pm2](#option-d--vps--pm2)
7. [Deploy the admin panel](#7-deploy-the-admin-panel)
   - [Option A — Vercel](#option-a--vercel)
   - [Option B — Docker](#option-b--docker)
8. [Razorpay (payments + webhook)](#8-razorpay-payments--webhook)
9. [Cloudflare R2 (media storage)](#9-cloudflare-r2-media-storage)
10. [Firebase Cloud Messaging (FCM)](#10-firebase-cloud-messaging-fcm)
11. [MSG91 SMS (OTP)](#11-msg91-sms-otp)
12. [Reverse proxy + TLS (nginx)](#12-reverse-proxy--tls-nginx)
13. [Flutter release build (Android)](#13-flutter-release-build-android)
14. [Post-deploy verification](#14-post-deploy-verification)
15. [Operations: backups, logs, upgrades](#15-operations-backups-logs-upgrades)

---

## 1. Architecture recap

```
Flutter app  ──REST + Socket.IO──▶  Backend (Node/Express, Prisma, Socket.IO)
            ◀──FCM push──────────   │   ├─ PostgreSQL  (Prisma)
Next.js admin ──REST (admin JWT)─▶  │   ├─ Razorpay    (orders, capture, webhook, payouts)
                                    │   ├─ Cloudflare R2 (presigned media uploads)
                                    │   ├─ Firebase Admin (FCM push)
                                    └─  └─ MSG91       (SMS OTP)
```

Public hostnames you will provision (adapt to your domain):

| Service  | Hostname (example)            | Behind nginx?  |
|----------|-------------------------------|----------------|
| Backend  | `api.companionranchi.com`     | yes (proxy + WS upgrade) |
| Admin    | `admin.companionranchi.com`   | yes (or Vercel) |
| Media    | `media.companionranchi.com`   | Cloudflare R2 public domain |

---

## 2. Prerequisites

- **Node.js 20 LTS** and **npm 10+** (backend + admin).
- **PostgreSQL 15 or 16** (managed service strongly recommended).
- **Flutter 3.22+** with Android SDK + JDK 17 (release builds).
- A registered **domain** with DNS you control (A/AAAA + CNAME records).
- Accounts: **Razorpay** (live KYC-approved), **Cloudflare** (R2 enabled), **Firebase**
  (project + FCM), **MSG91** (DLT-approved sender + template), and a **Play Console** account.
- A Linux host (Ubuntu 22.04+) if self-hosting via Docker or pm2.

Generate strong secrets up front (run once, store in your secret manager):

```bash
# 3 separate 64-char hex secrets for JWT access / refresh / admin
node -e "for(const k of ['ACCESS','REFRESH','ADMIN']) console.log(k, require('crypto').randomBytes(48).toString('hex'))"
```

---

## 3. Provision PostgreSQL

Use a managed Postgres (Render/Railway/Neon/Supabase/RDS) or self-host. You need a database,
a least-privilege application user, and the `sslmode=require` connection string.

**Self-hosted (psql) quick path:**

```sql
CREATE DATABASE companion_ranchi;
CREATE USER companion_app WITH ENCRYPTED PASSWORD 'STRONG_RANDOM_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE companion_ranchi TO companion_app;
-- Postgres 15+: also grant schema rights so Prisma can create tables
\c companion_ranchi
GRANT ALL ON SCHEMA public TO companion_app;
```

Resulting `DATABASE_URL` (note `sslmode=require` for managed/remote DBs):

```
postgresql://companion_app:STRONG_RANDOM_PASSWORD@db-host:5432/companion_ranchi?schema=public&sslmode=require
```

Managed providers (Neon/Supabase/RDS) give you this string directly — just append
`&schema=public` if missing. Enable **automated daily backups** and **point-in-time recovery**
at the provider level now (see [§15](#15-operations-backups-logs-upgrades)).

---

## 4. Environment variables

Copy [`deploy/.env.production.example`](./.env.production.example) to your secret store (never
commit a filled `.env`). Variable **names** match [`/.env.example`](../.env.example) exactly so
the backend's zod config (`src/config`) validates them unchanged. Critical production values:

| Var | Production value |
|-----|------------------|
| `NODE_ENV` | `production` |
| `API_BASE_URL` | `https://api.companionranchi.com` |
| `ADMIN_URL` | `https://admin.companionranchi.com` |
| `DATABASE_URL` | managed Postgres URL with `sslmode=require` |
| `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` / `ADMIN_JWT_SECRET` | unique 64+ char random hex (never the dev defaults) |
| `OTP_CONSOLE` | `false` (must send real SMS in prod) |
| `MSG91_AUTH_KEY` / `MSG91_SENDER_ID` / `MSG91_TEMPLATE_ID` | from MSG91 ([§11](#11-msg91-sms-otp)) |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | **live** keys (`rzp_live_…`) |
| `RAZORPAY_WEBHOOK_SECRET` | the secret you set on the webhook ([§8](#8-razorpay-payments--webhook)) |
| `R2_*` | Cloudflare R2 bucket + S3 creds ([§9](#9-cloudflare-r2-media-storage)) |
| `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_PROJECT_ID` | service-account path + project id ([§10](#10-firebase-cloud-messaging-fcm)) |
| `CORS_ORIGINS` | `https://admin.companionranchi.com` (+ app web origin if any) |
| `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` | the first super-admin login (rotate after first login) |

The admin (Next.js) needs `NEXT_PUBLIC_API_BASE_URL=https://api.companionranchi.com` at
**build time** (it is inlined into the client bundle).

---

## 5. Database: migrate + seed

From `backend/` with `DATABASE_URL` pointing at the **production** DB:

```bash
cd backend
npm ci                         # clean, lockfile-exact install
npx prisma generate            # generate the Prisma client
npx prisma migrate deploy      # apply committed migrations (NEVER `migrate dev` in prod)
npm run seed                    # categories, settings, first admin (idempotent upsert)
```

- `prisma migrate deploy` only applies already-committed migrations from
  `backend/prisma/migrations` — it never prompts and never drops data.
- The seed creates the fixed **categories** (`coffee-partner`, `movie-partner`,
  `shopping-partner`, `event-companion`, `city-guide`, `travel-companion`,
  `networking-partner`), the **settings** keys (`commission_rate=20`, `referral_reward=100`,
  `min_payout=500`, `booking_durations=[1,2,4,6]`, `cities=["Ranchi"]`), and the first
  **admin_user** from `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD`.
- **Rotate the seed admin password** immediately after first login.

Run migrations as a **release step** (Render/Railway pre-deploy command, or a one-off job)
so app instances never race to migrate.

---

## 6. Deploy the backend

The backend listens on `PORT` (default `4000`), exposes REST under `/api`, Socket.IO on the
same HTTP server, and a health check at `GET /health`. It needs `DATABASE_URL` plus all
provider secrets from [§4](#4-environment-variables).

### Option A — Docker / docker-compose

A multi-stage `Dockerfile` lives in `backend/` and `admin/` (built by other modules). The repo
root [`docker-compose.yml`](../docker-compose.yml) wires Postgres + Redis + backend + admin.
For a single-host production deploy:

```bash
# On the server, with a production .env at repo root:
docker compose pull            # if using a registry; otherwise compose builds locally
docker compose build backend admin
docker compose up -d postgres redis

# one-off release step: run migrations + seed inside the backend image
docker compose run --rm backend sh -c "npx prisma migrate deploy && npm run seed"

docker compose up -d backend admin
docker compose ps
docker compose logs -f backend
```

Put [nginx.conf](./nginx.conf) in front for TLS + the Socket.IO WebSocket upgrade
([§12](#12-reverse-proxy--tls-nginx)). Override `DATABASE_URL` to your managed DB if you are
not using the bundled Postgres container.

### Option B — Render

Use [`deploy/render.yaml`](./render.yaml) (Render Blueprint) for a one-click stack:
Postgres + backend web service + admin web service.

1. Push the repo to GitHub.
2. Render → **New → Blueprint** → pick the repo. Render reads `render.yaml`.
3. Render auto-creates the Postgres instance and injects `DATABASE_URL`.
4. Fill the **non-generated** secrets in the dashboard (Razorpay live keys, R2, Firebase,
   MSG91). JWT secrets are auto-generated by the blueprint (`generateValue: true`).
5. The backend service runs `npx prisma migrate deploy && npm run seed` as its
   **preDeployCommand**, then `npm start`.
6. Add custom domains `api.` and `admin.` in each service's **Settings → Custom Domains**;
   Render provisions TLS automatically.

Render's proxy supports WebSockets natively, so Socket.IO works without extra config.

### Option C — Railway

1. `railway init` (or create a project in the dashboard) and add a **PostgreSQL** plugin —
   Railway sets `DATABASE_URL`.
2. Create a service from the repo with root directory `backend`.
   - Build: `npm ci && npx prisma generate`
   - Pre-deploy / release: `npx prisma migrate deploy && npm run seed`
   - Start: `npm start`
3. Add all secrets under the service **Variables** tab.
4. Create a second service for `admin` (root `admin`), build `npm ci && npm run build`,
   start `npm start`, with `NEXT_PUBLIC_API_BASE_URL` set to the backend's public URL.
5. Generate public domains for both services (Settings → Networking). Railway terminates TLS
   and supports WebSocket upgrades.

### Option D — VPS + pm2

On Ubuntu 22.04 (Node 20 installed via nodesource):

```bash
# as a non-root deploy user
git clone <your-repo> /opt/companion-ranchi
cd /opt/companion-ranchi/backend
cp /opt/companion-ranchi/deploy/.env.production.example .env   # then edit with real secrets
npm ci
npx prisma generate
npx prisma migrate deploy
npm run seed

# install pm2 and start with the bundled config
sudo mkdir -p /var/log/companion && sudo chown "$USER" /var/log/companion
npm i -g pm2
pm2 start /opt/companion-ranchi/deploy/ecosystem.config.js
pm2 save
pm2 startup systemd                     # run the printed command to enable boot persistence
```

The bundled [`deploy/ecosystem.config.js`](./ecosystem.config.js) runs the backend via
`npm start` (single instance, fork mode, auto-restart, log files under `/var/log/companion`).
It defaults to `instances: 1`.

> **Socket.IO + cluster:** multiple workers need a shared adapter so a message published on
> one worker reaches sockets on another. Provision **Redis** and configure the Socket.IO Redis
> adapter (`REDIS_URL`) before scaling `instances > 1`. For a single small instance, set
> `instances: 1` and you can skip Redis.

Then put nginx in front ([§12](#12-reverse-proxy--tls-nginx)).

---

## 7. Deploy the admin panel

Next.js (App Router). Build-time it needs `NEXT_PUBLIC_API_BASE_URL`.

### Option A — Vercel

1. Import the repo in Vercel; set **Root Directory** to `admin`.
2. Framework preset: **Next.js**. Build `npm run build`, install `npm ci`.
3. Env vars (Production): `NEXT_PUBLIC_API_BASE_URL=https://api.companionranchi.com`.
4. Add `admin.companionranchi.com` as a custom domain.
5. Ensure the backend's `CORS_ORIGINS` includes the admin origin and that admin JWT cookies
   use `Secure; SameSite` appropriate for cross-subdomain (or send the token via header).

### Option B — Docker

`admin/Dockerfile` produces a standalone Next.js server. Build with the API URL baked in:

```bash
docker build -t companion-admin \
  --build-arg NEXT_PUBLIC_API_BASE_URL=https://api.companionranchi.com ./admin
docker run -d --name companion-admin -p 3000:3000 companion-admin
```

Proxy `admin.companionranchi.com` → `127.0.0.1:3000` via nginx ([§12](#12-reverse-proxy--tls-nginx)).

---

## 8. Razorpay (payments + webhook)

Bookings settle exclusively through Razorpay (no cash — auditable trail per
[docs/SAFETY.md](../docs/SAFETY.md)). Flow: `POST /payments/order` → Razorpay checkout →
`POST /payments/verify` (signature check) → capture → booking `CONFIRMED`. The webhook is the
**authoritative** capture/refund confirmation.

1. Razorpay Dashboard → switch to **Live mode** (complete business KYC first).
2. **Settings → API Keys → Generate Live Key.** Copy:
   - `RAZORPAY_KEY_ID` = `rzp_live_…`
   - `RAZORPAY_KEY_SECRET` = the secret (shown once).
3. **Settings → Webhooks → Add New Webhook:**
   - **Webhook URL:** `https://api.companionranchi.com/api/payments/webhook`
   - **Secret:** generate a strong random string → set the **same** value as
     `RAZORPAY_WEBHOOK_SECRET` in the backend env. The backend verifies the
     `X-Razorpay-Signature` header against the **raw** request body using this secret.
   - **Active events:** `payment.captured`, `payment.failed`, `payment.authorized`,
     `refund.processed`, `refund.failed`, `order.paid`.
4. Ensure your reverse proxy forwards the **raw** body to `/api/payments/webhook` (do not let
   any middleware re-encode it) — signature verification needs byte-exact bytes. nginx with a
   plain `proxy_pass` preserves the body as-is.
5. (Optional) **RazorpayX** for automated companion payouts: set `RAZORPAYX_ACCOUNT_NUMBER`.
   Without it, payouts are processed manually by an admin via `/admin/payouts/:id/process`.

Verify with Razorpay's **"Send test webhook"** button and confirm a `200` in backend logs.

---

## 9. Cloudflare R2 (media storage)

Profile photos, KYC docs, and chat images upload directly from clients via **presigned PUT**
URLs (`POST /uploads/presign` → `PUT` to the URL → store the returned public URL).

1. Cloudflare Dashboard → **R2 → Create bucket**: name `companion-ranchi`
   (matches `R2_BUCKET`). Choose a region close to your users.
2. **Public access:** attach a **custom domain** to the bucket, e.g.
   `media.companionranchi.com` (R2 → bucket → Settings → Public access → Connect Domain).
   Set `R2_PUBLIC_BASE_URL=https://media.companionranchi.com`.
3. **API token / S3 credentials:** R2 → **Manage R2 API Tokens → Create** with
   *Object Read & Write* on this bucket. Copy:
   - `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`
   - `R2_ACCOUNT_ID` (Cloudflare account id)
   - `R2_ENDPOINT=https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com`
4. **CORS** (R2 → bucket → Settings → CORS policy) so the app/admin can `PUT` directly:

```json
[
  {
    "AllowedOrigins": [
      "https://admin.companionranchi.com",
      "https://app.companionranchi.com",
      "capacitor://localhost",
      "http://localhost:3000"
    ],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }
]
```

> Native Flutter (Dio) uploads are not browser-CORS-bound, but keep the web/admin origins here
> so the admin panel and any web client can upload. Never make KYC documents publicly listable;
> only objects whose URL is stored should be served, and consider a separate private prefix for
> KYC with short-lived signed GET URLs if your moderation flow requires it.

---

## 10. Firebase Cloud Messaging (FCM)

Push notifications (bookings, payments, chat, SOS) go through Firebase Admin SDK on the
backend and FCM on the device.

1. [Firebase Console](https://console.firebase.google.com) → create/select a project. Note the
   **Project ID** → `FIREBASE_PROJECT_ID`.
2. **Project Settings → Service accounts → Generate new private key.** Download the JSON.
3. Deliver the JSON to the backend **as a secret file** (do **not** commit it — it is
   git-ignored as `firebase-service-account.json`). Two patterns:
   - **File path:** mount/copy it and set `FIREBASE_SERVICE_ACCOUNT=/etc/secrets/firebase-service-account.json`.
   - **Inline (Render/Railway):** store the JSON in a secret env var and write it to a file at
     boot, or base64-encode it. The backend reads the path in `FIREBASE_SERVICE_ACCOUNT`.
4. **Android app:** in the same Firebase project, register the Android app with your release
   package name (e.g. `com.companionranchi.app`), download `google-services.json`, and place it
   at `mobile/android/app/google-services.json` (git-ignored — see [§13](#13-flutter-release-build-android)).
5. (iOS later) upload the APNs auth key under Cloud Messaging settings.

---

## 11. MSG91 SMS (OTP)

Login uses mobile OTP. In production `OTP_CONSOLE=false` so OTPs are sent via MSG91 (India,
DLT-compliant).

1. Create an [MSG91](https://msg91.com) account; complete **DLT registration** (mandatory for
   transactional SMS in India) for your entity and sender.
2. **Auth key:** MSG91 → API → copy the **Auth Key** → `MSG91_AUTH_KEY`.
3. **Sender ID:** your approved 6-char header (e.g. `CMPRNC`) → `MSG91_SENDER_ID`.
4. **OTP template:** create a DLT-approved OTP template with a `{{otp}}` variable, e.g.
   *"Your Companion Ranchi verification code is {{otp}}. Valid for 5 minutes. Do not share it."*
   Copy the **Template ID** → `MSG91_TEMPLATE_ID`.
5. Keep OTP settings: `OTP_TTL_SECONDS=300`, `OTP_LENGTH=6`, `OTP_MAX_ATTEMPTS=5`.
6. Test end-to-end: `POST /api/auth/otp/request` with a real number, confirm the SMS arrives,
   then `POST /api/auth/otp/verify`.

If MSG91 is unset while `OTP_CONSOLE=false`, OTP requests will fail — verify keys before launch.

---

## 12. Reverse proxy + TLS (nginx)

Use [`deploy/nginx.conf`](./nginx.conf) as the server-block template. It:

- terminates TLS for `api.` and `admin.`,
- proxies `api.` → backend `:4000` with **WebSocket upgrade** for Socket.IO,
- proxies `admin.` → Next.js `:3000`,
- preserves the **raw body** and client IP for the Razorpay webhook.

Issue certificates with Let's Encrypt:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.companionranchi.com -d admin.companionranchi.com
sudo systemctl reload nginx
certbot renew --dry-run    # confirm auto-renewal works
```

DNS: point `api` and `admin` A/AAAA records at the server IP; point `media` (CNAME) at the
Cloudflare R2 custom domain.

---

## 13. Flutter release build (Android)

Produce a signed App Bundle (`.aab`) for the Play Store.

**1. Generate an upload keystore** (store the keystore + passwords in your secret manager —
losing it means you cannot update the app):

```bash
keytool -genkey -v -keystore ~/companion-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias companion-upload
```

**2. Configure signing** — create `mobile/android/key.properties` (git-ignored; add it to
`.gitignore` if not already):

```properties
storePassword=********
keyPassword=********
keyAlias=companion-upload
storeFile=/absolute/path/to/companion-upload.jks
```

Wire it into `mobile/android/app/build.gradle` (`signingConfigs.release` reading
`key.properties`, used by `buildTypes.release`). This is in the mobile module; do not edit it
from deploy — just ensure the keystore + `key.properties` are present on the build machine.

**3. Place Firebase config:** copy `google-services.json` (from [§10](#10-firebase-cloud-messaging-fcm))
to `mobile/android/app/google-services.json` (git-ignored).

**4. Set the production API base URL** for the app build. The app reads its base URL from
`--dart-define` (see `mobile/lib/core/env`), so pass it at build time — no source edits:

```bash
cd mobile
flutter pub get
flutter analyze                              # must be clean
flutter test                                  # if tests exist

flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.companionranchi.com \
  --dart-define=ENV=production
# output: build/app/outputs/bundle/release/app-release.aab
```

For sideload/QA testing build an APK instead:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.companionranchi.com --dart-define=ENV=production
```

**5. Upload `app-release.aab`** to the **Play Console** (Internal testing → Closed → Production).
In the data-safety/content sections, declare this as an **18+ companionship/social** app, not
adult content, and link the **Terms** (18+ + companionship-only) and **Privacy Policy** /
**Refund Policy** (see [production-checklist.md](./production-checklist.md)). Enable **Play App
Signing** so Google manages the app signing key.

---

## 14. Post-deploy verification

Smoke-test the live stack:

```bash
# Liveness
curl -fsS https://api.companionranchi.com/health

# Public config (categories, durations, cities, commissionRate, minAge)
curl -fsS https://api.companionranchi.com/api/meta/config | jq

# OTP request (expect success + an SMS to a real number in prod)
curl -fsS -X POST https://api.companionranchi.com/api/auth/otp/request \
  -H 'content-type: application/json' -d '{"mobileNumber":"+9199xxxxxxxx"}'
```

Then in the browser:

- Admin loads at `https://admin.companionranchi.com`, log in with the seed admin, **rotate the
  password**.
- Razorpay test webhook returns `200` in logs.
- Socket.IO connects from the app (chat sends `message:new` to the peer).
- A test booking respects **public-place-only** and **18+** validation (try an invalid place
  type / under-18 DOB and confirm rejection).

---

## 15. Operations: backups, logs, upgrades

- **Backups:** enable provider automated daily backups + PITR. For self-hosted, schedule
  `pg_dump` (encrypted, offsite) and **test a restore** quarterly.
- **Migrations on upgrade:** always run `npx prisma migrate deploy` as a release step before
  the new app version serves traffic. Never `migrate dev`/`db push` against prod.
- **Logs/monitoring:** ship backend logs (pino/JSON) to your platform's log drain; add uptime
  checks on `/health`; track error rates and Razorpay webhook failures.
- **Secret rotation:** rotate JWT secrets (forces re-login), Razorpay keys, R2 tokens, and the
  Firebase key on a schedule; rotate the seed admin password immediately after launch.
- **Zero-downtime:** with pm2 cluster or multiple Render/Railway instances, deploy rolling;
  ensure Socket.IO uses the Redis adapter when running >1 instance.

See the full launch gate in [production-checklist.md](./production-checklist.md).
