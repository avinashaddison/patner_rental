# Safety & Policy — Companion Ranchi

This product is a **companionship / social-activity marketplace**. It is **not** an escort
or adult-services platform. The following rules are **enforced in code**, not just policy text.

## Hard rules (enforced server-side)

1. **Adults only (18+).** Registration rejects any `dateOfBirth` under `MIN_AGE` (18). Age is
   recomputed server-side; client value is never trusted.
2. **Companionship only.** Categories are a fixed seeded list (coffee, movie, shopping, event,
   city guide, travel, networking). Free-text activity is validated against an allowed list.
   No category or activity may imply sexual/escort services.
3. **Public places only.** `meetingPlaceType` must be one of an allowed public-place list
   (Mall, Cafe, Restaurant, Public Event, Park, Co-working, Hotel Lobby, Tourist Spot).
   Private residences/hotels rooms are rejected.
4. **Verified companions.** A companion profile is only discoverable/bookable when
   `status = APPROVED` and KYC (`GOVERNMENT_ID` + `SELFIE`) is approved by an admin.
5. **Online payments only.** No cash flow is recorded; all bookings settle through Razorpay
   so there is an auditable trail.

## Safety features

- **KYC**: mandatory government ID + selfie verification for companions.
- **Emergency SOS**: available during an active booking; captures geolocation, alerts admin
  and (optionally) an emergency contact in real time.
- **Report user**: categories Harassment, Fake Profile, Abuse, Spam, Other — reviewable by admin.
- **Block user**: available everywhere; blocked users cannot message or book each other.
- **Audit trail**: booking status history, immutable wallet ledger, payment records.
- **Content moderation hooks**: chat image uploads and profile photos pass through a
  moderation checkpoint (pluggable) before becoming public.

## Abuse handling

Admins can suspend companions, block users, resolve reports, and ban repeat offenders.
Repeated valid reports auto-flag an account for review. All money movement is reversible
by admin via refund.
