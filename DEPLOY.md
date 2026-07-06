# Deploying the backend to Render (for multi-device testing)

Goal: put the backend on a public HTTPS URL so two (or more) phones can use the
app from any network, not just the same Wi-Fi as your PC.

## Why Render + Singapore

The Supabase Postgres is in `ap-southeast-1` (Singapore). Deploying the API in
Render's **Singapore** region puts it next to the DB, so queries drop from ~1.8s
(from your PC in India) to milliseconds. This is both the deploy step *and* the
real fix for app slowness.

## One-time setup

1. **Push the repo to GitHub** (Render deploys from a Git host):
   ```
   # from dev/companion-ranchi
   git add -A && git commit -m "Deploy prep: render.yaml + Dockerfile"
   git remote add origin https://github.com/<you>/companion-ranchi.git
   git push -u origin main
   ```
   `.env` is git-ignored, so no secrets are pushed. Verify with `git status`.

2. **Create the service on Render** → New → **Blueprint** → pick the repo.
   Render reads `render.yaml` and provisions `companion-ranchi-api` (Singapore,
   Starter plan). Starter (not Free) matters: Free instances sleep after 15 min,
   which drops the IMAP mail-watcher and the payment webhook.

3. **Set the environment variables** (Render → the service → Environment). Copy
   the *values* from `backend/.env`. `PORT` is set by Render automatically — do
   not add it. Group by need:

   **Required to boot**
   - `DATABASE_URL`, `DIRECT_URL`
   - `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `ADMIN_JWT_SECRET`
   - `JWT_ACCESS_TTL`, `JWT_REFRESH_TTL`
   - `CORS_ORIGINS` — include the admin panel origin (see step 5)
   - `API_BASE_URL` — set to the Render URL once known (see step 4)
   - `SUPABASE_URL`, `SUPABASE_JWKS_URL`, `SUPABASE_SECRET_KEY`, `SUPABASE_PUBLISHABLE_KEY`

   **Payments (the flow you're testing)**
   - `UPIQR_VPA`, `UPIQR_PAYEE_NAME`
   - `MAIL_IMAP_USER`, `MAIL_IMAP_PASS` (Gmail app password)
   - `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`
   - `UPIGATEWAY_KEY` (drop `UPIGATEWAY_REDIRECT_URL` — prod uses the real URL)

   **Media / uploads**
   - `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`,
     `R2_PUBLIC_BASE_URL`, `R2_ENDPOINT`

   **Feature integrations (copy whatever is set)**
   - Auth/OTP: `GOOGLE_OAUTH_CLIENT_ID/SECRET/REDIRECT_URI`, `APP_OAUTH_SCHEME`,
     `MSG91_*`, `OTP_*`
   - Calls: `AGORA_APP_ID`, `AGORA_APP_CERTIFICATE`
   - Push: `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT`
   - Maps: `MAPBOX_TOKEN`
   - Business: `DEFAULT_CITY`, `DEFAULT_COMMISSION_RATE`, `MIN_AGE`,
     `MIN_PAYOUT_AMOUNT`, `REFERRAL_REWARD_AMOUNT`, `APP_NAME`
   - Admin seed (first deploy): `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD`

4. **First deploy** → Render builds and gives a URL like
   `https://companion-ranchi-api.onrender.com`. Set `API_BASE_URL` to it and
   redeploy so absolute URLs (OAuth callback, UPI redirect) are correct.

5. **CORS + admin panel**: if you also deploy the admin panel (Vercel/Render
   static), add its URL to `CORS_ORIGINS`. For backend-only testing this can
   stay as-is.

6. **Point the app at the Render URL** and rebuild the APK:
   ```
   flutter build apk --release \
     --dart-define=API_BASE_URL=https://companion-ranchi-api.onrender.com \
     --dart-define=SOCKET_URL=https://companion-ranchi-api.onrender.com
   ```
   Install that APK on **both** devices. They now work from any network.

7. **Payment webhook**: in the UPIGateway dashboard set the webhook to
   `https://companion-ranchi-api.onrender.com/api/payments/upi/webhook`
   (replaces the temporary cloudflared tunnel URL). The self-hosted UPI-QR
   mail-watcher needs no webhook — it runs inside the service.

## After deploy — sanity checks
- `https://<url>/health` → `{"success":true,...}`
- Render logs show `[mailwatch] watching … INBOX` (mail-watcher connected)
- Log in on both devices; one books, the other (a companion) receives it.

## Notes
- The DB schema is managed with `prisma db push` from your machine, never from
  Render — the Dockerfile/start command does NOT run migrations.
- Seed data (`npm run seed`) also runs from your machine against the same DB;
  it's already seeded, so you likely don't need to re-run it.
