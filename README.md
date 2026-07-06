# Companion Ranchi

A premium, **non-adult** companionship marketplace (Ranchi MVP). Verified adults book
**verified companions** for social activities — coffee, movies, shopping, events, city
tours, networking and conversation.

> **Policy (enforced in code):** This platform is **strictly for companionship and social
> activities**. It does **not** facilitate sexual or escort services. Meetings are restricted
> to **public places only**. All users must be verified adults (18+). KYC, SOS, reporting and
> blocking are first-class safety features.

---

## Monorepo layout

```
companion-ranchi/
├── backend/          Node.js + Express REST API, Prisma (PostgreSQL), Socket.IO, Razorpay, R2, FCM
├── mobile/           Flutter app (Material 3, light/dark) — Customer + Companion
├── admin/            Next.js admin panel
├── database/         Reference SQL schema + seed data (Prisma is the source of truth)
├── deploy/           Dockerfiles, nginx, CI, production deployment config
├── docs/             Contracts: DATA_MODEL.md, API.md, ARCHITECTURE.md, SAFETY.md
├── docker-compose.yml
└── .env.example
```

## Tech stack

| Layer        | Technology |
|--------------|------------|
| Mobile       | Flutter, Material 3, Riverpod, go_router, Dio |
| Backend      | Node.js, Express, Prisma ORM |
| Database     | PostgreSQL |
| Storage      | Cloudflare R2 (S3-compatible) |
| Realtime     | Socket.IO |
| Notifications| Firebase Cloud Messaging (FCM) |
| Admin        | Next.js (App Router), Tailwind CSS |
| Payments     | Razorpay (orders, capture, webhooks, payouts) |
| Auth         | Mobile OTP + JWT (access + refresh) |

## User roles

- **Customer** — search, book, chat, pay, review, manage bookings, wallet, referrals.
- **Companion** — register, KYC, profile, photos, rates, availability, accept bookings, chat, payouts.
- **Admin** — approve companions, verify KYC, manage users/bookings/complaints/payments, analytics.

## Quick start (local)

```bash
# 0. Prereqs: Node 20+, PostgreSQL 15+, Flutter 3.22+, Docker (optional)
cp .env.example .env            # fill in secrets (dev works with placeholders + OTP console mode)

# 1. Infra (Postgres) via Docker
docker compose up -d postgres

# 2. Backend
cd backend
npm install
npx prisma migrate dev --name init
npm run seed                    # categories, settings, demo admin/customer/companions
npm run dev                     # http://localhost:4000  (Swagger at /api/docs)

# 3. Admin panel
cd ../admin
npm install
npm run dev                     # http://localhost:3000

# 4. Mobile app
cd ../mobile
flutter pub get
flutter run                     # point API_BASE_URL at http://10.0.2.2:4000 for Android emulator
```

In **development**, OTPs are printed to the backend console (no SMS provider needed) and
Razorpay runs in test mode. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/API.md](docs/API.md).

## Documentation

- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — entities, enums, relationships (Prisma contract)
- [docs/API.md](docs/API.md) — REST + Socket.IO contract (consumed by mobile + admin)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design, flows, money math
- [docs/SAFETY.md](docs/SAFETY.md) — safety & anti-abuse policy enforced in code
- [deploy/README.md](deploy/README.md) — production deployment

## License

Proprietary — © Companion Ranchi. All rights reserved.
