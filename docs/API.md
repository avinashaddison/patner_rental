# REST + Realtime API Contract — Companion Ranchi

Base URL: `${API_BASE_URL}/api` (e.g. `http://localhost:4000/api`). JSON only.
Auth: `Authorization: Bearer <accessToken>` (user JWT) or admin JWT for `/admin/*`.

## Conventions

**Success**
```json
{ "success": true, "data": { ... }, "meta": { "page": 1, "limit": 20, "total": 57 } }
```
**Error**
```json
{ "success": false, "error": { "code": "VALIDATION_ERROR", "message": "human readable", "details": [] } }
```
Codes: `VALIDATION_ERROR` (400), `UNAUTHORIZED` (401), `FORBIDDEN` (403), `NOT_FOUND` (404),
`CONFLICT` (409), `RATE_LIMITED` (429), `PAYMENT_ERROR` (402), `INTERNAL` (500).

Pagination query: `?page=1&limit=20&sort=createdAt:desc`. Files are uploaded via presigned
R2 URLs (`POST /uploads/presign` → `PUT` to URL → store returned public URL).

---

## 1. Auth  `/auth`

| Method | Path | Auth | Body / Notes |
|---|---|---|---|
| POST | `/auth/otp/request` | – | `{ mobileNumber }` → sends OTP (dev: console). `{ requestId, expiresIn }` |
| POST | `/auth/otp/verify` | – | `{ mobileNumber, otp }` → `{ accessToken, refreshToken, user, isNewUser }` |
| POST | `/auth/register` | – | Complete profile for new user: `{ fullName, gender, dateOfBirth, city, role, referralCode? }` (requires temp token from verify when isNewUser). Validates age ≥ 18. |
| POST | `/auth/refresh` | – | `{ refreshToken }` → `{ accessToken, refreshToken }` |
| POST | `/auth/logout` | user | invalidates refresh token, clears fcmToken |
| GET  | `/auth/me` | user | current user (+companion if applicable) |
| POST | `/auth/fcm-token` | user | `{ fcmToken }` |

## 2. Users / Profile  `/users`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/users/me` | user | profile |
| PATCH | `/users/me` | user | `{ fullName?, city?, email?, profilePhotoUrl? }` |
| GET | `/users/:id` | user | public profile (limited) |
| POST | `/users/block` | user | `{ blockedId }` |
| DELETE | `/users/block/:blockedId` | user | unblock |
| GET | `/users/blocks` | user | list blocked users |

## 3. Companions  `/companions`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/companions` | optional | **Search/list.** Query: `q, category, interest, city, minRate, maxRate, minRating, online, featured, lat, lng, sort, page, limit`. Returns cards. |
| GET | `/companions/featured` | optional | featured companions |
| GET | `/companions/popular-nearby` | optional | `?lat&lng` location-based |
| GET | `/companions/categories` | – | category list |
| GET | `/companions/:id` | optional | full profile (photos, reviews, availability, rate, isVerified) |
| GET | `/companions/:id/availability` | optional | `?date=YYYY-MM-DD` → available time slots (excludes booked) |
| GET | `/companions/:id/reviews` | optional | paginated reviews |
| POST | `/companions/me` | companion | create/onboard companion profile |
| GET | `/companions/me/profile` | companion | own profile |
| PATCH | `/companions/me` | companion | `{ aboutMe?, languages?, interests?, hourlyRate?, city?, categoryIds? }` |
| PATCH | `/companions/me/online` | companion | `{ isOnline }` |
| POST | `/companions/me/photos` | companion | `{ photoUrl, isPrimary? }` |
| DELETE | `/companions/me/photos/:photoId` | companion | |
| PUT | `/companions/me/availability` | companion | `{ slots: [{ dayOfWeek, startTime, endTime }] }` |

**Companion card shape**
```json
{ "id":"...","name":"Aisha","age":24,"city":"Ranchi","photoUrl":"...","rating":4.8,
  "ratingCount":42,"hourlyRate":600,"isVerified":true,"isOnline":true,"isFeatured":true,
  "categories":["coffee-partner","city-guide"],"distanceKm":2.4 }
```

## 4. Bookings  `/bookings`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/bookings/quote` | customer | `{ companionId, durationHours }` → price breakdown (no DB write) |
| POST | `/bookings` | customer | Create booking: `{ companionId, categoryId?, activity, durationHours, bookingDate, startTime, meetingLocation, meetingPlaceType, notes? }` → booking with `PENDING` status + Razorpay order. Validates slot availability + public place. |
| GET | `/bookings` | user | list mine (role-aware: customer→their bookings, companion→received). Query `?status` |
| GET | `/bookings/:id` | user | detail (+ statusHistory) |
| POST | `/bookings/:id/accept` | companion | PENDING/CONFIRMED → CONFIRMED |
| POST | `/bookings/:id/reject` | companion | → CANCELLED (+ refund if paid) |
| POST | `/bookings/:id/start` | companion | CONFIRMED → IN_PROGRESS |
| POST | `/bookings/:id/complete` | companion | IN_PROGRESS → COMPLETED (triggers payout credit + referral check) |
| POST | `/bookings/:id/cancel` | customer | `{ reason }` (refund policy applies) |

**Booking status machine:** `PENDING → CONFIRMED → IN_PROGRESS → COMPLETED`; any pre-completion
state → `CANCELLED`; paid+cancelled/rejected → `REFUNDED`.

## 5. Payments  `/payments`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/payments/order` | customer | `{ bookingId }` → `{ razorpayOrderId, amount, currency, keyId }` |
| POST | `/payments/verify` | customer | `{ razorpayOrderId, razorpayPaymentId, razorpaySignature }` → verifies signature, captures, confirms booking |
| POST | `/payments/webhook` | – (signature) | Razorpay webhook (raw body). Handles capture/refund. |
| GET | `/payments/:bookingId` | user | payment status |

## 6. Wallet & Payouts  `/wallet`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/wallet` | user | `{ balance, pendingBalance, totalEarned, totalWithdrawn }` |
| GET | `/wallet/transactions` | user | paginated ledger |
| POST | `/wallet/payouts` | companion | `{ amount, method, upiId? | bankAccountName?, bankAccountNumber?, ifsc? }` |
| GET | `/wallet/payouts` | companion | payout history |

## 7. Companion dashboard  `/companion`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/companion/dashboard` | companion | `{ totalEarnings, pendingEarnings, withdrawnEarnings, upcomingBookings, ratingAvg, ratingCount, reviewCount }` |
| GET | `/companion/earnings` | companion | breakdown + recent transactions |
| GET | `/companion/bookings` | companion | received bookings by status |

## 8. Reviews  `/reviews`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/reviews` | customer | `{ bookingId, behaviourRating, communicationRating, punctualityRating, comment? }` (only COMPLETED bookings; one per booking) |
| GET | `/reviews/companion/:companionId` | optional | paginated |

## 9. Chat  `/chat`  (+ Socket.IO)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/chat/conversations` | user | list with last message + unread count |
| POST | `/chat/conversations` | user | `{ peerUserId, bookingId? }` → get-or-create |
| GET | `/chat/conversations/:id/messages` | user | paginated history |
| POST | `/chat/conversations/:id/messages` | user | `{ type, content?, imageUrl? }` (REST fallback; prefer socket) |
| POST | `/chat/conversations/:id/read` | user | mark read |

**Socket.IO** (namespace `/`, auth via `{ auth: { token } }`):
- client→server: `message:send` `{ conversationId, type, content?, imageUrl? }`,
  `typing:start`/`typing:stop` `{ conversationId }`, `message:read` `{ conversationId }`,
  `presence:ping`.
- server→client: `message:new` `{ message }`, `message:sent` `{ tempId, message }`,
  `typing` `{ conversationId, userId, isTyping }`, `message:read` `{ conversationId, userId }`,
  `presence:update` `{ userId, isOnline }`, `notification:new` `{ notification }`.

## 10. KYC  `/kyc`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/kyc/submit` | companion | `{ documentType, documentUrl, documentNumber? }` (GOVERNMENT_ID + SELFIE) |
| GET | `/kyc/status` | companion | overall KYC status + docs |

## 11. Notifications  `/notifications`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/notifications` | user | paginated |
| POST | `/notifications/:id/read` | user | |
| POST | `/notifications/read-all` | user | |
| GET | `/notifications/unread-count` | user | `{ count }` |

## 12. Reports / Safety  `/reports`, `/sos`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/reports` | user | `{ reportedUserId, bookingId?, category, description? }` |
| GET | `/reports/mine` | user | |
| POST | `/sos` | user | `{ bookingId?, latitude?, longitude?, message? }` → alerts admin + emergency contact |
| GET | `/sos/active` | user | |
| POST | `/sos/:id/cancel` | user | |

## 13. Referrals  `/referrals`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/referrals/me` | user | `{ referralCode, totalReferred, totalEarned, referrals[] }` |
| POST | `/referrals/apply` | user | `{ code }` (during onboarding) |

## 14. Support  `/support`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/support/tickets` | user | `{ subject, description, priority? }` |
| GET | `/support/tickets` | user | mine |
| GET | `/support/tickets/:id` | user | with messages |
| POST | `/support/tickets/:id/messages` | user | `{ message }` |

## 15. Uploads  `/uploads`

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/uploads/presign` | user | `{ fileName, contentType, folder }` → `{ uploadUrl, publicUrl, key }` (R2 presigned PUT) |

## 16. Meta  `/meta`

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/meta/config` | – | public config: categories, durations, cities, commissionRate, minAge |
| GET | `/health` | – | liveness |

---

## ADMIN API  `/admin`  (admin JWT)

| Method | Path | Notes |
|---|---|---|
| POST | `/admin/auth/login` | `{ email, password }` → admin JWT |
| GET | `/admin/auth/me` | current admin |
| GET | `/admin/dashboard` | `{ revenue, totalUsers, activeBookings, newRegistrations, ... }` |
| GET | `/admin/analytics/revenue` | `?period=daily|weekly|monthly|yearly` time series |
| GET | `/admin/users` | search/paginate users; `?role&blocked&q` |
| GET | `/admin/users/:id` | detail |
| POST | `/admin/users/:id/block` | `{ reason }` |
| POST | `/admin/users/:id/unblock` | |
| GET | `/admin/companions` | `?status` (pending/approved/...) |
| GET | `/admin/companions/:id` | detail incl. KYC |
| POST | `/admin/companions/:id/approve` | |
| POST | `/admin/companions/:id/reject` | `{ reason }` |
| POST | `/admin/companions/:id/suspend` | `{ reason }` |
| POST | `/admin/companions/:id/feature` | `{ isFeatured }` |
| GET | `/admin/kyc` | `?status=PENDING` queue |
| POST | `/admin/kyc/:id/approve` | |
| POST | `/admin/kyc/:id/reject` | `{ reason }` |
| GET | `/admin/bookings` | `?status&q` |
| GET | `/admin/bookings/:id` | |
| POST | `/admin/bookings/:id/cancel` | `{ reason }` |
| POST | `/admin/bookings/:id/refund` | `{ amount? }` |
| GET | `/admin/payments` | ledger |
| GET | `/admin/payouts` | `?status` |
| POST | `/admin/payouts/:id/process` | mark processing/completed |
| POST | `/admin/payouts/:id/reject` | `{ reason }` |
| GET | `/admin/reports` | complaints `?status` |
| POST | `/admin/reports/:id/resolve` | `{ resolutionNotes }` |
| GET | `/admin/support/tickets` | `?status` |
| POST | `/admin/support/tickets/:id/reply` | `{ message }` |
| POST | `/admin/support/tickets/:id/status` | `{ status }` |
| GET | `/admin/sos` | active SOS alerts |
| POST | `/admin/sos/:id/resolve` | |
| GET | `/admin/settings` | all settings |
| PUT | `/admin/settings/:key` | `{ value }` (e.g. commission_rate) |
| GET | `/admin/analytics/overview` | KPIs |
