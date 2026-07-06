// Centralized, validated environment configuration.
// Loads .env once and exposes a typed `config` object used everywhere.
import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const bool = (v, def = false) => {
  if (v === undefined || v === null || v === '') return def;
  return ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
};

const envSchema = z.object({
  NODE_ENV: z.string().default('development'),
  PORT: z.coerce.number().default(4000),
  APP_NAME: z.string().default('Companion Ranchi'),
  API_BASE_URL: z.string().default('http://localhost:4000'),
  ADMIN_URL: z.string().default('http://localhost:3000'),

  DATABASE_URL: z.string().default('postgresql://companion:companion@localhost:5432/companion_ranchi?schema=public'),

  JWT_ACCESS_SECRET: z.string().default('change_me_access_secret_dev'),
  JWT_REFRESH_SECRET: z.string().default('change_me_refresh_secret_dev'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  ADMIN_JWT_SECRET: z.string().default('change_me_admin_secret_dev'),

  OTP_CONSOLE: z.string().optional(),
  OTP_TTL_SECONDS: z.coerce.number().default(300),
  OTP_LENGTH: z.coerce.number().default(6),
  OTP_MAX_ATTEMPTS: z.coerce.number().default(5),
  MSG91_AUTH_KEY: z.string().optional(),
  MSG91_SENDER_ID: z.string().optional(),
  MSG91_TEMPLATE_ID: z.string().optional(),

  RAZORPAY_KEY_ID: z.string().default('rzp_test_xxxxxxxx'),
  RAZORPAY_KEY_SECRET: z.string().default('xxxxxxxx'),
  RAZORPAY_WEBHOOK_SECRET: z.string().default('xxxxxxxx'),
  RAZORPAYX_ACCOUNT_NUMBER: z.string().optional(),

  // UPIGateway (ekqr.in) — UPI QR payments. Enabled when the key is set.
  UPIGATEWAY_KEY: z.string().optional(),
  // The gateway rejects localhost redirect URLs — override with any public URL
  // in dev; in production leave unset to use the API's own /upi/redirect page.
  UPIGATEWAY_REDIRECT_URL: z.string().optional(),

  // Self-hosted UPI QR payments: dynamic QR to our own VPA, confirmed by
  // reading the bank's credit-alert emails (IMAP) and matching amount + UTR.
  UPIQR_VPA: z.string().optional(),
  UPIQR_PAYEE_NAME: z.string().default('Companion Ranchi'),
  UPIQR_EXPIRY_MIN: z.coerce.number().default(15),
  MAIL_IMAP_HOST: z.string().default('imap.gmail.com'),
  MAIL_IMAP_PORT: z.coerce.number().default(993),
  MAIL_IMAP_USER: z.string().optional(),
  MAIL_IMAP_PASS: z.string().optional(),
  MAIL_ALERT_FROM: z.string().default('alerts@axis.bank.in'),

  R2_ACCOUNT_ID: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().default('companion-ranchi'),
  R2_PUBLIC_BASE_URL: z.string().default('https://media.companionranchi.com'),
  R2_ENDPOINT: z.string().optional(),

  CLOUDINARY_URL: z.string().optional(),

  // Mapbox access token — used by the tracking proxy for Directions (route +
  // ETA) and Geocoding (meeting-place autocomplete). Optional: when unset the
  // proxy returns no route/suggestions and the client degrades gracefully.
  MAPBOX_TOKEN: z.string().optional(),

  FIREBASE_SERVICE_ACCOUNT: z.string().optional(),
  FIREBASE_PROJECT_ID: z.string().optional(),

  // Google OAuth (Authorization Code flow) — replaces Firebase for Google login.
  // The client secret stays server-side; the app never sees it.
  GOOGLE_OAUTH_CLIENT_ID: z.string().optional(),
  GOOGLE_OAUTH_CLIENT_SECRET: z.string().optional(),
  // Must exactly match an "Authorized redirect URI" on the Web OAuth client.
  GOOGLE_OAUTH_REDIRECT_URI: z.string().optional(),
  // Custom scheme the backend bounces back to after sign-in (the mobile app).
  APP_OAUTH_SCHEME: z.string().default('companionranchi'),

  DEFAULT_COMMISSION_RATE: z.coerce.number().default(20),
  REFERRAL_REWARD_AMOUNT: z.coerce.number().default(100),
  MIN_PAYOUT_AMOUNT: z.coerce.number().default(500),
  DEFAULT_CITY: z.string().default('Ranchi'),
  MIN_AGE: z.coerce.number().default(18),

  CORS_ORIGINS: z.string().default('http://localhost:3000,http://localhost:5173'),

  SEED_ADMIN_EMAIL: z.string().default('admin@companionranchi.com'),
  SEED_ADMIN_PASSWORD: z.string().default('Admin@12345'),
}).passthrough();

const env = envSchema.parse(process.env);

export const config = {
  env: env.NODE_ENV,
  isProd: env.NODE_ENV === 'production',
  isDev: env.NODE_ENV !== 'production',
  port: env.PORT,
  appName: env.APP_NAME,
  apiBaseUrl: env.API_BASE_URL,
  adminUrl: env.ADMIN_URL,
  databaseUrl: env.DATABASE_URL,

  jwt: {
    accessSecret: env.JWT_ACCESS_SECRET,
    refreshSecret: env.JWT_REFRESH_SECRET,
    accessTtl: env.JWT_ACCESS_TTL,
    refreshTtl: env.JWT_REFRESH_TTL,
    adminSecret: env.ADMIN_JWT_SECRET,
  },

  otp: {
    console: bool(env.OTP_CONSOLE, true),
    ttlSeconds: env.OTP_TTL_SECONDS,
    length: env.OTP_LENGTH,
    maxAttempts: env.OTP_MAX_ATTEMPTS,
    msg91: {
      authKey: env.MSG91_AUTH_KEY || '',
      senderId: env.MSG91_SENDER_ID || 'CMPRNC',
      templateId: env.MSG91_TEMPLATE_ID || '',
    },
  },

  razorpay: {
    keyId: env.RAZORPAY_KEY_ID,
    keySecret: env.RAZORPAY_KEY_SECRET,
    webhookSecret: env.RAZORPAY_WEBHOOK_SECRET,
    payoutAccountNumber: env.RAZORPAYX_ACCOUNT_NUMBER || '',
  },

  upigateway: {
    key: env.UPIGATEWAY_KEY || '',
    enabled: Boolean(env.UPIGATEWAY_KEY),
    redirectUrl: env.UPIGATEWAY_REDIRECT_URL || '',
  },

  upiqr: {
    vpa: env.UPIQR_VPA || '',
    payeeName: env.UPIQR_PAYEE_NAME,
    expiryMin: env.UPIQR_EXPIRY_MIN,
    enabled: Boolean(env.UPIQR_VPA),
  },

  mailwatch: {
    host: env.MAIL_IMAP_HOST,
    port: env.MAIL_IMAP_PORT,
    user: env.MAIL_IMAP_USER || '',
    pass: env.MAIL_IMAP_PASS || '',
    alertFrom: env.MAIL_ALERT_FROM,
    enabled: Boolean(env.MAIL_IMAP_USER && env.MAIL_IMAP_PASS),
  },

  r2: {
    accountId: env.R2_ACCOUNT_ID || '',
    accessKeyId: env.R2_ACCESS_KEY_ID || '',
    secretAccessKey: env.R2_SECRET_ACCESS_KEY || '',
    bucket: env.R2_BUCKET,
    publicBaseUrl: env.R2_PUBLIC_BASE_URL,
    endpoint: env.R2_ENDPOINT || '',
  },

  cloudinary: {
    url: env.CLOUDINARY_URL,
  },

  maps: {
    mapboxToken: env.MAPBOX_TOKEN || '',
  },

  firebase: {
    serviceAccount: env.FIREBASE_SERVICE_ACCOUNT || '',
    projectId: env.FIREBASE_PROJECT_ID || '',
  },

  googleOAuth: {
    clientId: env.GOOGLE_OAUTH_CLIENT_ID || '',
    clientSecret: env.GOOGLE_OAUTH_CLIENT_SECRET || '',
    redirectUri:
      env.GOOGLE_OAUTH_REDIRECT_URI ||
      `${env.API_BASE_URL}/api/auth/google/callback`,
    appScheme: env.APP_OAUTH_SCHEME,
    configured: Boolean(env.GOOGLE_OAUTH_CLIENT_ID && env.GOOGLE_OAUTH_CLIENT_SECRET),
  },

  agora: {
    appId: env.AGORA_APP_ID || '',
    appCertificate: env.AGORA_APP_CERTIFICATE || '',
    enabled: Boolean(env.AGORA_APP_ID && env.AGORA_APP_CERTIFICATE),
  },

  supabase: {
    url: env.SUPABASE_URL || '',
    // Prefer an explicit JWKS URL; otherwise derive it from the project URL.
    jwksUrl:
      env.SUPABASE_JWKS_URL
      || (env.SUPABASE_URL ? `${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1/.well-known/jwks.json` : ''),
    publishableKey: env.SUPABASE_PUBLISHABLE_KEY || '',
    secretKey: env.SUPABASE_SECRET_KEY || '',
    enabled: Boolean(env.SUPABASE_URL || env.SUPABASE_JWKS_URL),
  },

  business: {
    commissionRate: env.DEFAULT_COMMISSION_RATE,
    referralReward: env.REFERRAL_REWARD_AMOUNT,
    minPayout: env.MIN_PAYOUT_AMOUNT,
    defaultCity: env.DEFAULT_CITY,
    minAge: env.MIN_AGE,
  },

  corsOrigins: env.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),

  seed: {
    adminEmail: env.SEED_ADMIN_EMAIL,
    adminPassword: env.SEED_ADMIN_PASSWORD,
  },
};

export default config;
