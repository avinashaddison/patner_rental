# Production / Launch Checklist — Companion Ranchi

Gate every production launch (and major release) on this checklist. It encodes the
**safety contract** from [docs/SAFETY.md](../docs/SAFETY.md): adults only (18+),
companionship/social activities only, public-place meetings only, verified companions,
online-payments-only. Do not launch with any **Blocker** unchecked.

Legend: **[B]** Blocker (no launch) · **[H]** High · **[M]** Medium.

---

## 1. Secrets & configuration

- [ ] **[B]** No dev defaults in prod: `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
      `ADMIN_JWT_SECRET` are unique 64+ char random hex (not the `change_me_*` values).
- [ ] **[B]** `NODE_ENV=production` and `OTP_CONSOLE=false` (OTPs sent via SMS, never logged).
- [ ] **[B]** Razorpay **live** keys (`rzp_live_…`) set; `RAZORPAY_WEBHOOK_SECRET` matches the
      dashboard webhook secret exactly.
- [ ] **[B]** No secret committed to git: `.env`, `firebase-service-account.json`,
      `*.jks`/`key.properties`, `google-services.json` are git-ignored and absent from history.
- [ ] **[H]** `DATABASE_URL` uses a least-privilege user and `sslmode=require`.
- [ ] **[H]** `CORS_ORIGINS` lists only trusted origins (admin panel, web client) — no `*`.
- [ ] **[H]** Seed admin (`SEED_ADMIN_*`) password rotated immediately after first login.
- [ ] **[M]** All third-party creds (R2, Firebase, MSG91) live in a secret manager, not files
      in the repo or plaintext on disk where avoidable.

## 2. Database & migrations

- [ ] **[B]** `npx prisma migrate deploy` run against prod (no pending/drifted migrations).
- [ ] **[B]** `npm run seed` applied: 7 categories, settings keys (`commission_rate=20`,
      `referral_reward=100`, `min_payout=500`, `booking_durations=[1,2,4,6]`,
      `cities=["Ranchi"]`), first admin.
- [ ] **[B]** **Automated daily backups + PITR** enabled; a **restore has been tested**.
- [ ] **[H]** Migrations run as a release step (not racing app instances); no `migrate dev` /
      `db push` against prod.
- [ ] **[M]** Connection pool sized for the instance count; pooler (PgBouncer/provider) in
      place if many serverless connections.

## 3. Safety rules (enforced in code) — must be verified live

- [ ] **[B]** **18+ only:** registering with a `dateOfBirth` under 18 is **rejected**
      server-side (age recomputed, client value not trusted). Tested with an under-18 DOB.
- [ ] **[B]** **Public places only:** a booking with a non-allowed `meetingPlaceType`
      (e.g. a private residence / hotel room) is **rejected**; allowed list = Mall, Cafe,
      Restaurant, Public Event, Park, Co-working, Hotel Lobby, Tourist Spot.
- [ ] **[B]** **Companionship only:** `activity` validated against the allowed list; fixed
      seeded categories only — nothing implying sexual/escort services is creatable.
- [ ] **[B]** **Verified companions only:** a companion is discoverable/bookable only when
      `status=APPROVED` **and** KYC (`GOVERNMENT_ID` + `SELFIE`) approved. Unapproved
      companions do not appear in `/companions` search.
- [ ] **[B]** **Online payments only:** bookings settle via Razorpay; no cash path exists.
- [ ] **[H]** **SOS** works during an active booking (captures geolocation, alerts admin);
      visible in `/admin/sos`.
- [ ] **[H]** **Report** + **Block** function; blocked users cannot message or book each other.
- [ ] **[M]** Content-moderation checkpoint runs on profile photos and chat images before they
      become public.

## 4. API & realtime hardening

- [ ] **[B]** **Rate limits** active on auth/OTP (per-mobile + per-IP) to stop OTP abuse and
      brute force; `OTP_MAX_ATTEMPTS=5`, `OTP_TTL_SECONDS=300`. Global rate limit on the API.
- [ ] **[B]** Razorpay webhook verifies `X-Razorpay-Signature` over the **raw** body; nginx
      forwards the body unbuffered (see [nginx.conf](./nginx.conf)).
- [ ] **[B]** Payment **signature verification** enforced on `/payments/verify`; bookings only
      `CONFIRMED` after a verified capture.
- [ ] **[H]** JWT TTLs sane (`15m` access / `30d` refresh) with refresh rotation; logout
      invalidates the refresh token and clears `fcmToken`.
- [ ] **[H]** Socket.IO authenticated via JWT (`{ auth: { token } }`); unauthenticated sockets
      rejected. Redis adapter configured if running >1 instance.
- [ ] **[H]** Security headers + HTTPS-only (HSTS) at the proxy; HTTP redirects to HTTPS.
- [ ] **[M]** Input validation (zod) on every route; consistent error envelope
      (`{ success:false, error:{ code, message, details } }`).
- [ ] **[M]** Idempotency: duplicate webhook deliveries and double `verify` calls do not
      double-credit wallets or re-trigger referral rewards.

## 5. Money integrity

- [ ] **[B]** Money math matches [DATA_MODEL.md](../docs/DATA_MODEL.md): `totalAmount =
      hourlyRate * durationHours`, `commissionAmount = round2(total * rate/100)`,
      `companionPayout = total - commission`; all `Decimal(10,2)` INR (never floats).
- [ ] **[B]** On `COMPLETED`: companion wallet credited `companionPayout` (BOOKING_EARNING),
      platform `COMMISSION` recorded; on `REFUNDED`: customer refunded `totalAmount`.
- [ ] **[H]** Referral reward (₹100) credits the **referrer** only on the referee's **first
      COMPLETED booking**, once.
- [ ] **[H]** Wallet ledger is append-only/immutable; `balanceAfter` consistent with running
      balance.
- [ ] **[M]** Payout requests honor `min_payout` (₹500) and cannot exceed available balance.

## 6. Integrations live-tested

- [ ] **[B]** OTP SMS delivered via MSG91 to a real number (DLT template approved).
- [ ] **[B]** Razorpay test webhook returns `200`; a real captured payment confirms a booking.
- [ ] **[H]** R2 presigned upload (`/uploads/presign` → PUT) works from app and admin; public
      URL serves; CORS allows the web origins; KYC docs not publicly listable.
- [ ] **[H]** FCM push delivered to a device for booking/chat/SOS events.
- [ ] **[M]** `/meta/config` returns correct categories, durations, cities, commissionRate,
      minAge.

## 7. Monitoring, logging, alerting

- [ ] **[B]** Uptime check on `GET /health` with alerting.
- [ ] **[H]** Structured logs shipped to a log drain; **no secrets/OTPs/PII** in logs.
- [ ] **[H]** Error tracking (e.g. Sentry) on backend + admin with alert thresholds.
- [ ] **[H]** Alert on Razorpay webhook failures and payout/refund errors.
- [ ] **[M]** Dashboards for revenue, active bookings, signups, error rate; on-call/runbook
      documented.

## 8. Moderation & abuse handling

- [ ] **[B]** Admin can **suspend** companions, **block** users, **resolve reports**, and
      **refund** bookings (abuse is reversible).
- [ ] **[H]** Reports queue (`/admin/reports`) and SOS queue (`/admin/sos`) monitored with an
      SLA; repeated valid reports auto-flag an account for review.
- [ ] **[H]** KYC review queue (`/admin/kyc`) staffed; companions cannot go live without
      approval.
- [ ] **[M]** Documented takedown/ban process for policy violations; escalation contact for
      SOS / safety incidents.

## 9. Legal & policy (must ship with the app)

- [ ] **[B]** **Terms of Service** state explicitly: **18+ only**, **companionship/social
      activities only** (not escort/sexual services), **public-place meetings only**, and that
      violating accounts are banned. Linked in app + admin + store listing.
- [ ] **[B]** **Privacy Policy** (data collected: mobile, KYC docs, location for SOS; retention;
      third parties: Razorpay/R2/Firebase/MSG91) published and linked.
- [ ] **[B]** **Refund / cancellation policy** published, consistent with the booking refund
      logic (cancel/reject → CANCELLED/REFUNDED per policy).
- [ ] **[H]** **Community / safety guidelines** (public meetings, no harassment, reporting,
      SOS) shown to users.
- [ ] **[H]** Play Store listing declares an **18+ companionship/social** app (not adult
      content); data-safety form accurate; links to ToS + Privacy + Refund.
- [ ] **[M]** Companion contractor terms (independent contractors, payout/commission, tax/PAN
      where applicable) in place.

## 10. Mobile release

- [ ] **[B]** Release `.aab` signed with the **upload keystore**; keystore + passwords backed
      up in a secret manager (loss = cannot update the app).
- [ ] **[B]** App points at `https://api.companionranchi.com` (built with
      `--dart-define=API_BASE_URL=...`); no localhost/test endpoints.
- [ ] **[H]** `flutter analyze` clean; `google-services.json` present (FCM works on release).
- [ ] **[H]** Play **App Signing** enabled; internal testing pass before production rollout.
- [ ] **[M]** Crash reporting enabled; version/build numbers bumped.

---

### Sign-off

| Area | Owner | Date | OK |
|------|-------|------|----|
| Secrets & config | | | |
| Database & backups | | | |
| Safety rules verified | | | |
| API/realtime hardening | | | |
| Money integrity | | | |
| Integrations | | | |
| Monitoring | | | |
| Moderation | | | |
| Legal & policy | | | |
| Mobile release | | | |

> No production launch proceeds while any **[B] Blocker** remains unchecked.
