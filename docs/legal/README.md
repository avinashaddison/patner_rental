# Legal documents — Companion Ranchi

This folder holds the **canonical, user-facing legal documents** for Companion
Ranchi. They are the source of truth that should be:

1. **Hosted publicly** (e.g. `https://companionranchi.com/legal/terms`) so the
   app, the Play Store listing and the website all point at one URL.
2. **Mirrored in-app** by `mobile/lib/features/settings/presentation/legal_screen.dart`
   (the offline/bundled renderer). When you change a document here, update the
   matching sections in `legal_screen.dart` so the two stay consistent.
3. Used to fill the Google **Play Data Safety** form (the Privacy Policy in
   particular).

| Document | File | In-app `LegalDocument` |
| --- | --- | --- |
| Terms of Service | [terms-of-service.md](terms-of-service.md) | `terms` |
| Privacy Policy | [privacy-policy.md](privacy-policy.md) | `privacy` |
| Refund & Cancellation Policy | [refund-and-cancellation-policy.md](refund-and-cancellation-policy.md) | `refund` |
| Community & Safety Guidelines | [community-guidelines.md](community-guidelines.md) | `safety` |

## ⚠️ Before you publish — required review

These drafts are written to be accurate to how the app actually works, but they
are **not a substitute for legal advice**. For an 18+, in-person companionship
marketplace operating in India you should have a lawyer review them, and you are
legally required (IT Rules 2021) to appoint a **Grievance Officer** and publish
their contact details.

## 🔧 Placeholders to fill in

Every document uses `{{DOUBLE_BRACE}}` placeholders. Search-and-replace these
across all four files before publishing:

| Placeholder | Meaning | Example |
| --- | --- | --- |
| `{{LEGAL_ENTITY_NAME}}` | Registered business / proprietor name that operates Companion Ranchi | `Addison Media (Proprietorship)` |
| `{{REGISTERED_ADDRESS}}` | Registered business address | `Ranchi, Jharkhand, India` |
| `{{SUPPORT_EMAIL}}` | Public support email | `support@companionranchi.com` |
| `{{GRIEVANCE_OFFICER_NAME}}` | Named Grievance Officer (IT Rules 2021) | `—` |
| `{{GRIEVANCE_OFFICER_EMAIL}}` | Grievance Officer contact email | `grievance@companionranchi.com` |
| `{{GOVERNING_CITY}}` | Jurisdiction city for disputes | `Ranchi` |
| `{{GOVERNING_STATE}}` | Jurisdiction state | `Jharkhand` |
| `{{EFFECTIVE_DATE}}` | Effective / last-updated date | `29 June 2026` |
| `{{WEBSITE_URL}}` | Public website base URL | `https://companionranchi.com` |

## Decisions baked into these drafts (confirm they match your intent)

- **Refund windows**: full refund > 24h before start; 50% between 6–24h; none
  under 6h or no-show. Change in both `refund-and-cancellation-policy.md` and
  `legal_screen.dart` (`LegalDocument.refund`) if your policy differs.
- **Commission**: a platform commission is taken from each completed booking
  (the exact rate is a runtime setting, not stated as a fixed number here).
- **Data retention**: KYC documents are retained only while needed for
  verification/compliance and deleted on account closure (see the KYC
  retention work item — the erasure code must actually exist for this to be
  true).
- **Payments**: online-only via Razorpay; no cash is ever collected on-platform.
