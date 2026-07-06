# Data Model — Companion Ranchi

Source of truth for the database. The backend implements this as `backend/prisma/schema.prisma`
(PostgreSQL). Field names below are the **API/JSON** names (camelCase). DB columns are snake_case
via Prisma `@map`. All ids are UUID v4 strings. All money is `Decimal(10,2)` in **INR**.
Timestamps are ISO-8601 UTC. Every table has `createdAt`; mutable tables have `updatedAt`.

## Enums

| Enum | Values |
|------|--------|
| `Role` | `CUSTOMER`, `COMPANION`, `ADMIN` |
| `Gender` | `MALE`, `FEMALE`, `OTHER` |
| `KycStatus` | `PENDING`, `SUBMITTED`, `APPROVED`, `REJECTED` |
| `KycDocType` | `GOVERNMENT_ID`, `SELFIE` |
| `CompanionStatus` | `PENDING`, `APPROVED`, `REJECTED`, `SUSPENDED` |
| `BookingStatus` | `PENDING`, `CONFIRMED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`, `REFUNDED` |
| `PaymentStatus` | `CREATED`, `AUTHORIZED`, `CAPTURED`, `FAILED`, `REFUNDED` |
| `TransactionType` | `CREDIT`, `DEBIT`, `PAYOUT`, `REFUND`, `COMMISSION`, `REFERRAL_REWARD`, `BOOKING_EARNING` |
| `TransactionStatus` | `PENDING`, `COMPLETED`, `FAILED` |
| `PayoutMethod` | `BANK_TRANSFER`, `UPI` |
| `PayoutStatus` | `REQUESTED`, `PROCESSING`, `COMPLETED`, `FAILED`, `REJECTED` |
| `ReportCategory` | `HARASSMENT`, `FAKE_PROFILE`, `ABUSE`, `SPAM`, `OTHER` |
| `ReportStatus` | `OPEN`, `REVIEWING`, `RESOLVED`, `DISMISSED` |
| `TicketStatus` | `OPEN`, `IN_PROGRESS`, `RESOLVED`, `CLOSED` |
| `TicketPriority` | `LOW`, `MEDIUM`, `HIGH`, `URGENT` |
| `NotificationType` | `BOOKING`, `PAYMENT`, `CHAT`, `SYSTEM`, `KYC`, `REVIEW`, `REFERRAL`, `SOS` |
| `MessageType` | `TEXT`, `IMAGE` |
| `SosStatus` | `ACTIVE`, `RESOLVED`, `CANCELLED` |
| `AdminRole` | `SUPER_ADMIN`, `ADMIN`, `SUPPORT`, `FINANCE` |
| `ReferralStatus` | `PENDING`, `COMPLETED`, `EXPIRED` |

## Tables / Models

### users
Core account for every human (customer or companion). Admins use `admin_users`.
- `id`, `mobileNumber` (unique), `fullName`, `gender`, `dateOfBirth` (date), `city`, `email?` (unique)
- `role` (Role, default CUSTOMER), `isMobileVerified` (bool), `profilePhotoUrl?`
- `fcmToken?`, `isBlocked` (bool), `blockedReason?`
- `referralCode` (unique, auto-generated), `referredById?` → users.id
- `lastActiveAt?`, `createdAt`, `updatedAt`
- Relations: `companion?` (1:1), `wallet?` (1:1), `kycDocuments[]`, `bookingsAsCustomer[]`,
  `notifications[]`, `payouts[]`, `transactions[]`, `sosAlerts[]`, referrals (made/received).

### companions
Extends a user with role=COMPANION. 1:1 with users.
- `id`, `userId` (unique → users.id), `aboutMe?`
- `languages` (string[]), `interests` (string[]), `hourlyRate` (Decimal, default 0), `city`
- `status` (CompanionStatus, default PENDING), `isOnline` (bool)
- `ratingAvg` (float), `ratingCount` (int), `totalBookings` (int), `totalEarnings` (Decimal)
- `isFeatured` (bool), `latitude?`, `longitude?`, `approvedAt?`, `rejectedReason?`
- Relations: `photos[]`, `categories[]` (via companion_categories), `availability[]`,
  `bookings[]`, `reviews[]`.
- **Derived in API:** `age` (from user.dateOfBirth), `name` (user.fullName), `isVerified`
  (status=APPROVED && KYC approved).

### categories
Fixed list of activity categories. Seeded.
- `id`, `slug` (unique), `name`, `iconUrl?`, `sortOrder`, `isActive`
- Seed slugs: `coffee-partner`, `movie-partner`, `shopping-partner`, `event-companion`,
  `city-guide`, `travel-companion`, `networking-partner`.

### companion_photos
- `id`, `companionId` → companions.id, `photoUrl`, `isPrimary` (bool), `sortOrder`, `createdAt`

### companion_categories (join)
- `id`, `companionId`, `categoryId`, unique(`companionId`,`categoryId`)

### companion_availability
Weekly recurring availability windows.
- `id`, `companionId`, `dayOfWeek` (0=Sun..6=Sat), `startTime` ("HH:mm"), `endTime` ("HH:mm"),
  `isAvailable` (bool, default true)

### kyc_documents
- `id`, `userId` → users.id, `docType` (KycDocType), `documentUrl`, `documentNumber?`
- `status` (KycStatus, default PENDING), `reviewedById?` (admin id), `reviewNotes?`, `reviewedAt?`

### bookings
- `id`, `bookingCode` (unique, e.g. `CR-7F3A2B`), `customerId` → users.id, `companionId` → companions.id
- `categoryId?` → categories.id, `activity` (string, e.g. "Coffee")
- `durationHours` (int: 1|2|4|6), `bookingDate` (date), `startTime` ("HH:mm"), `endTime` ("HH:mm")
- `meetingLocation` (string), `meetingPlaceType` (string: Mall|Cafe|Restaurant|Public Event|...)
- `hourlyRate` (Decimal snapshot), `totalAmount` (Decimal), `commissionRate` (float snapshot)
- `commissionAmount` (Decimal), `companionPayout` (Decimal)
- `status` (BookingStatus, default PENDING), `notes?`, `cancelledById?`, `cancellationReason?`, `completedAt?`
- Relations: `payment?` (1:1), `review?` (1:1), `statusHistory[]`.
- **Constraint:** meeting must be a public place (validated server-side).

### booking_status_history  (the `booking_status` table)
- `id`, `bookingId` → bookings.id, `status` (BookingStatus), `changedById?`, `note?`, `createdAt`

### payments
- `id`, `bookingId` (unique → bookings.id), `customerId`
- `razorpayOrderId?`, `razorpayPaymentId?`, `razorpaySignature?`
- `amount` (Decimal), `currency` (default "INR"), `status` (PaymentStatus, default CREATED)
- `method` (default "razorpay"), `capturedAt?`

### wallet
One per user. Companions accrue earnings here; customers hold referral/refund credit.
- `id`, `userId` (unique), `balance` (Decimal), `pendingBalance` (Decimal),
  `totalEarned` (Decimal), `totalWithdrawn` (Decimal), `currency` (default INR)

### transactions
Immutable ledger entries against a wallet.
- `id`, `walletId` → wallet.id, `userId`, `bookingId?`, `type` (TransactionType)
- `amount` (Decimal, signed by type), `balanceAfter` (Decimal)
- `status` (TransactionStatus, default COMPLETED), `reference?`, `description?`

### payouts
Companion withdrawal requests.
- `id`, `userId` → users.id, `amount` (Decimal), `method` (PayoutMethod)
- `bankAccountName?`, `bankAccountNumber?`, `ifsc?`, `upiId?`
- `status` (PayoutStatus, default REQUESTED), `processedById?`, `notes?`, `processedAt?`

### reviews
- `id`, `bookingId` (unique), `customerId`, `companionId`
- `behaviourRating` (1..5), `communicationRating` (1..5), `punctualityRating` (1..5)
- `overallRating` (float, avg of the three), `comment?`

### conversations
Chat thread between a customer and a companion.
- `id`, `customerId`, `companionId`, `bookingId?`, `lastMessage?`, `lastMessageAt?`
- unique(`customerId`,`companionId`)
- Relations: `messages[]`.

### messages
- `id`, `conversationId` → conversations.id, `senderId`, `receiverId`
- `type` (MessageType, default TEXT), `content?` (text), `imageUrl?`
- `isRead` (bool), `readAt?`

### notifications
- `id`, `userId`, `type` (NotificationType), `title`, `body`, `data?` (json), `isRead` (bool)

### reports
- `id`, `reporterId`, `reportedUserId`, `bookingId?`, `category` (ReportCategory)
- `description?`, `status` (ReportStatus, default OPEN), `reviewedById?`, `resolutionNotes?`, `resolvedAt?`

### blocks
- `id`, `blockerId`, `blockedId`, unique(`blockerId`,`blockedId`)

### support_tickets
- `id`, `userId`, `subject`, `description`, `status` (TicketStatus, default OPEN)
- `priority` (TicketPriority, default MEDIUM), `assignedToId?`, `resolvedAt?`
- Relations: `messages[]` (ticket_messages).

### ticket_messages
- `id`, `ticketId`, `senderId`, `message`, `createdAt`

### referrals
- `id`, `referrerId`, `referredId` (unique), `status` (ReferralStatus, default PENDING)
- `rewardAmount` (Decimal, default 100), `rewarded` (bool), `qualifyingBookingId?`, `rewardedAt?`

### sos_alerts
- `id`, `userId`, `bookingId?`, `latitude?`, `longitude?`, `status` (SosStatus, default ACTIVE)
- `message?`, `resolvedById?`, `resolvedAt?`

### admin_users
- `id`, `email` (unique), `passwordHash`, `name`, `role` (AdminRole, default ADMIN)
- `permissions` (string[]), `isActive` (bool), `lastLoginAt?`

### settings
Key/value runtime config (commission rate, referral reward, feature flags).
- `id`, `key` (unique), `value` (json), `description?`, `updatedById?`, `updatedAt`
- Seed keys: `commission_rate` (20), `referral_reward` (100), `min_payout` (500),
  `booking_durations` ([1,2,4,6]), `cities` (["Ranchi"]).

### otp_verifications
- `id`, `mobileNumber`, `otpHash`, `purpose` (default "login"), `expiresAt`
- `verified` (bool), `attempts` (int), `createdAt`

## Money math (single source of truth)

For a booking:
```
totalAmount      = hourlyRate * durationHours
commissionRate   = settings.commission_rate            (default 20%)
commissionAmount = round2(totalAmount * commissionRate / 100)
companionPayout  = totalAmount - commissionAmount
```
On booking **COMPLETED**: credit companion wallet `+companionPayout` (BOOKING_EARNING),
record platform `COMMISSION`. On **REFUNDED**: refund customer `+totalAmount` to source/wallet.
Referral reward (₹100) credits the **referrer** on the referee's **first COMPLETED booking**.
