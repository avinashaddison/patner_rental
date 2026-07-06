# Architecture — Companion Ranchi

## High-level

```
┌────────────┐     REST + Socket.IO      ┌─────────────────────────────┐
│ Flutter app │ ───────────────────────▶ │  Node.js / Express backend  │
│ (Customer + │ ◀─────────────────────── │  Prisma → PostgreSQL        │
│  Companion) │     FCM push             │  Socket.IO (chat/presence)  │
└────────────┘                           │  Razorpay (pay + payout)    │
┌────────────┐     REST (admin JWT)      │  Cloudflare R2 (media)      │
│ Next.js     │ ───────────────────────▶ │  Firebase Admin (FCM)       │
│ Admin panel │ ◀─────────────────────── └─────────────────────────────┘
└────────────┘
```

## Backend layering

```
src/
  config/        env loading + validation (zod), constants
  lib/           prisma client, jwt, otp, razorpay, r2 (S3), firebase, socket bootstrap, logger
  middleware/    auth (user/admin), role guard, error handler, rate limit, validate(zod), notFound
  validators/    zod request schemas per domain
  routes/        *.routes.js  (auto-mounted at /api/<name> by routes/index.js)
  controllers/   thin HTTP handlers (req→service→res)
  services/      business logic (transactions, money math, status machine)
  sockets/       chat + presence handlers
  jobs/          cron-ish tasks (e.g. auto-complete, payout reconcile)
  utils/         helpers (asyncHandler, apiResponse, pagination, codes)
```

Route auto-loading convention: every file `src/routes/<name>.routes.js` must
`export default router` (Express Router). `routes/index.js` mounts it at `/api/<name>`.
This lets feature modules be added without editing a shared file.

## Key flows

**Auth (OTP + JWT):** request OTP → verify → if new user, `register` to complete profile
(age ≥ 18 enforced) → issue access (15m) + refresh (30d) JWT. Refresh rotation on `/auth/refresh`.

**Booking + payment:**
1. `POST /bookings/quote` → price breakdown.
2. `POST /bookings` → validates availability + public meeting place → creates `PENDING`
   booking + Razorpay order.
3. Client pays via Razorpay checkout → `POST /payments/verify` (signature check) → payment
   `CAPTURED`, booking `CONFIRMED`, both parties notified (FCM + socket).
4. Companion `start` → `IN_PROGRESS`; `complete` → `COMPLETED`: companion wallet credited
   `companionPayout`, platform records `COMMISSION`, referral reward evaluated.
5. Cancel/reject before completion → `CANCELLED`/`REFUNDED` per refund policy.

**Money math:** see [DATA_MODEL.md](DATA_MODEL.md#money-math). Commission default 20%,
configurable via `settings.commission_rate`. All amounts `Decimal(10,2)` INR; never floats for money.

**Chat:** Socket.IO authenticated by JWT. `message:send` persists then emits `message:new`
to the peer (or FCM push if offline). Typing + read receipts + presence tracked in memory
(Redis adapter ready for scale-out).

**KYC:** companion uploads GOVERNMENT_ID + SELFIE (R2). Admin approves → companion becomes
verifiable; profile only goes live when companion `status=APPROVED` **and** KYC approved.

## Mobile (Flutter) layering

```
lib/
  core/        theme (M3 light/dark, purple gradient), router (go_router), api (Dio + interceptors),
               storage (secure token), constants, env, socket client, di (Riverpod providers)
  shared/      reusable widgets (cards, buttons, badges, ratings, loaders, empty states)
  features/    auth, onboarding, home, search, companion, booking, payment, chat, bookings,
               reviews, wallet, notifications, profile, settings, support, companion_dashboard, safety
```
State: Riverpod. Navigation: go_router with auth-redirect. Networking: Dio with JWT refresh
interceptor. Theme follows system; manual toggle persisted.

## Admin (Next.js) layering

App Router (`src/app`): `/login`, `/(dashboard)/...` route group with sidebar layout.
Pages: dashboard, companions, kyc, users, bookings, payments, payouts, complaints, support,
analytics, settings. Tailwind + a small UI kit. Auth via admin JWT in httpOnly cookie / header.

## Environments
- **dev:** OTP to console, Razorpay test keys, R2 optional (local fallback), FCM optional.
- **prod:** all providers configured; see [deploy/README.md](../deploy/README.md).
