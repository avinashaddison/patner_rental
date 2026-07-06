# Companion Ranchi — Backend

Express + Prisma (PostgreSQL) backend for **Companion Ranchi**, a non-adult companionship
marketplace (social activities only: coffee, movies, shopping, events, city tours, networking).
Users are 18+; meetings are public-places only. See [`../docs/SAFETY.md`](../docs/SAFETY.md).

## Stack
- **Node 20**, ESM (`"type": "module"`)
- **Express** REST API, **Socket.IO** realtime (chat + presence)
- **Prisma** ORM → **PostgreSQL**
- **Razorpay** (payments + payouts), **Cloudflare R2** (media), **Firebase Admin** (FCM)
- **Zod** validation, **JWT** auth (user + admin)

## Layout
```
src/
  config/        env loading + constants
  lib/           prisma, jwt, otp, razorpay, r2, firebase, socket, logger
  middleware/    auth, validate, error, rateLimit
  utils/         asyncHandler, apiResponse, pagination
  services/      ledger, notification, settings (+ feature services)
  routes/        *.routes.js  (auto-mounted at /api/<name>)
  controllers/   thin HTTP handlers
  validators/    zod schemas
  app.js         express assembly
  server.js      http + socket bootstrap
prisma/
  schema.prisma  full data model
  seed.js        idempotent seed
```

Routes are **auto-loaded**: drop `src/routes/<name>.routes.js` (default-exporting an Express
Router) and it mounts at `/api/<name>` — no shared file to edit.

## Prerequisites
- Node 20+
- PostgreSQL 16 (use `docker compose up -d postgres` from the repo root)

## Setup
```bash
# 1. install deps
npm install

# 2. configure env (from repo root)
cp ../.env.example ../.env     # dev defaults work out of the box (OTP_CONSOLE=true)

# 3. generate client + run migrations
npm run prisma:generate
npm run prisma:migrate         # creates the schema (dev)

# 4. seed demo data (admin, customer, 3 approved companions, categories, settings)
npm run seed

# 5. run
npm run dev                    # nodemon
# or
npm start
```

The API listens on `http://localhost:4000`.
- Health:  `GET /health`
- API root: `GET /api`

## Dev notes
- **OTP**: with `OTP_CONSOLE=true` the OTP is printed to the server log — no SMS provider needed.
- **Razorpay / R2 / FCM**: optional in dev. Missing config degrades gracefully (push becomes a no-op, etc.).
- **Money**: all amounts are `Decimal(10,2)` INR. Never use floats for money — use the ledger service.
- **Webhook**: `POST /api/payments/webhook` receives the **raw** body for signature verification.

## Seeded accounts
- **Admin**: `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` (default `admin@companionranchi.com` / `Admin@12345`)
- **Customer**: mobile `+919000000001`
- **Companions**: `+919000000101`, `+919000000102`, `+919000000103` (all APPROVED + KYC approved)

## Scripts
| Script | Description |
|---|---|
| `npm run dev` | start with nodemon |
| `npm start` | start server |
| `npm run seed` | seed the database (idempotent) |
| `npm run prisma:migrate` | run dev migrations |
| `npm run prisma:deploy` | apply migrations (prod) |
| `npm run prisma:generate` | generate Prisma client |
| `npm run prisma:studio` | open Prisma Studio |
| `npm run lint` | eslint |

## Docker
```bash
docker build -t companion-backend .
docker run --env-file ../.env -p 4000:4000 companion-backend
```
The image runs `prisma migrate deploy` before starting.

## Realtime (Socket.IO)
Connect with `{ auth: { token: <accessToken> } }`. Events per [`../docs/API.md`](../docs/API.md#9-chat-chat--socketio):
`message:send`, `typing:start/stop`, `message:read`, `presence:ping` →
`message:new`, `message:sent`, `typing`, `message:read`, `presence:update`, `notification:new`.
