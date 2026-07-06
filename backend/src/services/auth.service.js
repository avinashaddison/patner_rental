// Auth business logic: OTP issuance/verification, registration (18+ enforced),
// token issue/rotation, session lookup. Matches docs/API.md section 1 + docs/DATA_MODEL.md.
import jwt from 'jsonwebtoken';
import { customAlphabet } from 'nanoid';
import { prisma } from '../lib/prisma.js';
import { config } from '../config/index.js';
import { logger } from '../lib/logger.js';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../lib/jwt.js';
import {
  generateOtp,
  hashOtp,
  compareOtp,
  sendOtpSms,
} from '../lib/otp.js';
import { verifyIdToken } from '../lib/firebase.js';
import { verifySupabaseToken } from '../lib/supabase.js';
import { ApiError } from '../utils/apiResponse.js';

// Referral codes: unambiguous uppercase alphabet, fixed length 8.
const referralCodeGen = customAlphabet('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 8);

// Short-lived registration ("temp") token carried between /auth/otp/verify and
// /auth/register for users who don't have an account yet. Signed with the access
// secret but with a distinct type so it can never be used as an access token.
const REGISTER_TOKEN_TTL = '20m';

// The register token carries the verified IDENTITY of a not-yet-registered user
// between the sign-in step and POST /auth/register. Phone sign-up embeds
// `{ mobileNumber }`; Google sign-up embeds `{ email, fullName, profilePhotoUrl }`.
// A bare string is accepted for backwards-compat (treated as a mobile number).
function signRegisterToken(identity) {
  const id = typeof identity === 'string' ? { mobileNumber: identity } : (identity || {});
  return jwt.sign(
    {
      mobileNumber: id.mobileNumber || undefined,
      email: id.email || undefined,
      fullName: id.fullName || undefined,
      profilePhotoUrl: id.profilePhotoUrl || undefined,
      supabaseUserId: id.supabaseUserId || undefined,
      authProvider: id.authProvider || undefined,
      type: 'register',
    },
    config.jwt.accessSecret,
    { expiresIn: REGISTER_TOKEN_TTL },
  );
}

/** Verify a register/temp token and return the embedded identity. */
export function verifyRegisterToken(token) {
  const payload = jwt.verify(token, config.jwt.accessSecret);
  if (payload.type !== 'register' || (!payload.mobileNumber && !payload.email)) {
    throw new Error('Invalid registration token');
  }
  return {
    mobileNumber: payload.mobileNumber || null,
    email: payload.email || null,
    fullName: payload.fullName || null,
    profilePhotoUrl: payload.profilePhotoUrl || null,
    supabaseUserId: payload.supabaseUserId || null,
    authProvider: payload.authProvider || null,
  };
}

/** Compute integer age in whole years from a date of birth. */
export function computeAge(dateOfBirth) {
  const dob = new Date(dateOfBirth);
  const now = new Date();
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const m = now.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) age -= 1;
  return age;
}

/** Generate a referral code that is not already taken. */
async function generateUniqueReferralCode() {
  // Practically collision-free; loop a few times defensively.
  for (let i = 0; i < 6; i += 1) {
    const code = referralCodeGen();
    const exists = await prisma.user.findUnique({
      where: { referralCode: code },
      select: { id: true },
    });
    if (!exists) return code;
  }
  throw ApiError.internal('Could not allocate a referral code, please retry');
}

/** Shape the user object returned to clients (no sensitive internals). */
export function publicUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    mobileNumber: user.mobileNumber,
    fullName: user.fullName,
    gender: user.gender,
    dateOfBirth: user.dateOfBirth,
    city: user.city,
    email: user.email,
    username: user.username,
    role: user.role,
    isMobileVerified: user.isMobileVerified,
    profilePhotoUrl: user.profilePhotoUrl,
    referralCode: user.referralCode,
    referredById: user.referredById,
    isBlocked: user.isBlocked,
    lastActiveAt: user.lastActiveAt,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    age: user.dateOfBirth ? computeAge(user.dateOfBirth) : null,
    companion: user.companion ? publicCompanion(user.companion) : undefined,
  };
}

/** Username format rule (3-20 chars: lowercase letters, digits, underscore). */
export const USERNAME_REGEX = /^[a-z0-9_]{3,20}$/;

/**
 * Whether a @username is well-formed and not already taken. Used by the live
 * availability check on the registration screen.
 * @returns {Promise<{available:boolean, username:string, reason?:string}>}
 */
export async function isUsernameAvailable(raw) {
  const username = String(raw || '').trim().toLowerCase();
  if (!USERNAME_REGEX.test(username)) {
    return { available: false, username, reason: 'invalid_format' };
  }
  const taken = await prisma.user.findUnique({
    where: { username },
    select: { id: true },
  });
  return { available: !taken, username, reason: taken ? 'taken' : undefined };
}

/** Trimmed companion view embedded in /auth/me. */
export function publicCompanion(companion) {
  if (!companion) return null;
  return {
    id: companion.id,
    userId: companion.userId,
    aboutMe: companion.aboutMe,
    languages: companion.languages,
    interests: companion.interests,
    hourlyRate: companion.hourlyRate,
    city: companion.city,
    status: companion.status,
    isOnline: companion.isOnline,
    ratingAvg: companion.ratingAvg,
    ratingCount: companion.ratingCount,
    totalBookings: companion.totalBookings,
    totalEarnings: companion.totalEarnings,
    isFeatured: companion.isFeatured,
    approvedAt: companion.approvedAt,
    createdAt: companion.createdAt,
  };
}

function issueTokens(user) {
  return {
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  };
}

/**
 * Create an OTP challenge for a mobile number and deliver it.
 * @returns {{requestId:string, expiresIn:number}}
 */
export async function requestOtp(mobileNumber) {
  const otp = generateOtp();
  const otpHash = await hashOtp(otp);
  const ttl = config.otp.ttlSeconds;
  const expiresAt = new Date(Date.now() + ttl * 1000);

  const record = await prisma.otpVerification.create({
    data: {
      mobileNumber,
      otpHash,
      purpose: 'login',
      expiresAt,
      verified: false,
      attempts: 0,
    },
  });

  await sendOtpSms(mobileNumber, otp);

  return { requestId: record.id, expiresIn: ttl };
}

/**
 * Verify an OTP. On success:
 *  - existing user → issue access+refresh, mark isMobileVerified, return isNewUser=false.
 *  - new user      → return isNewUser=true + a short-lived registration token.
 * @returns {{isNewUser:boolean, accessToken?, refreshToken?, registerToken?, user?}}
 */
export async function verifyOtp(mobileNumber, otp) {
  const record = await prisma.otpVerification.findFirst({
    where: { mobileNumber, verified: false },
    orderBy: { createdAt: 'desc' },
  });

  if (!record) {
    throw ApiError.badRequest('No active OTP found. Please request a new one.');
  }

  if (record.expiresAt.getTime() < Date.now()) {
    throw ApiError.badRequest('OTP has expired. Please request a new one.');
  }

  if (record.attempts >= config.otp.maxAttempts) {
    throw ApiError.badRequest('Too many incorrect attempts. Please request a new OTP.');
  }

  const matches = await compareOtp(otp, record.otpHash);
  if (!matches) {
    await prisma.otpVerification.update({
      where: { id: record.id },
      data: { attempts: { increment: 1 } },
    });
    throw ApiError.badRequest('Incorrect OTP. Please try again.');
  }

  // Consume the OTP (single-use).
  await prisma.otpVerification.update({
    where: { id: record.id },
    data: { verified: true, attempts: { increment: 1 } },
  });

  const existing = await prisma.user.findUnique({
    where: { mobileNumber },
    include: { companion: true },
  });

  if (!existing) {
    return {
      isNewUser: true,
      registerToken: signRegisterToken(mobileNumber),
      user: null,
    };
  }

  const user = await prisma.user.update({
    where: { id: existing.id },
    data: { isMobileVerified: true, lastActiveAt: new Date() },
    include: { companion: true },
  });

  return {
    isNewUser: false,
    ...issueTokens(user),
    user: publicUser(user),
  };
}

/**
 * Log in / sign up via a Firebase ID token. The client completes sign-in with
 * Firebase (Google OAuth, or legacy phone OTP), then sends us the resulting ID
 * token; we verify it server-side and mint our OWN JWTs — mirroring verifyOtp's
 * existing/new-user branching so the rest of the app is unchanged.
 *
 * Identity resolution:
 *  - Google token → key by verified `email`.
 *  - Phone token  → key by canonical 10-digit `mobileNumber` (legacy/fallback).
 * @returns {{isNewUser:boolean, accessToken?, refreshToken?, registerToken?, user?}}
 */
export async function loginWithFirebase(idToken) {
  let decoded;
  try {
    decoded = await verifyIdToken(idToken);
  } catch (err) {
    if (err.code === 'firebase/not-configured') {
      throw ApiError.internal('Sign-in is not configured on the server.');
    }
    throw ApiError.unauthorized('Invalid or expired sign-in token.');
  }

  // --- Phone sign-in (legacy / fallback) ---------------------------------
  const e164 = decoded.phone_number; // e.g. +919876543210
  if (e164) {
    // Canonical bare 10-digit form — matches how the OTP flow stores numbers.
    const canonical = e164
      .replace(/\s|-/g, '')
      .replace(/^\+?91/, '')
      .replace(/^0/, '');

    // Try the canonical form first, then the raw E.164 (legacy records).
    let existing = null;
    for (const m of [canonical, e164]) {
      if (!m) continue;
      existing = await prisma.user.findUnique({
        where: { mobileNumber: m },
        include: { companion: true },
      });
      if (existing) break;
    }

    if (!existing) {
      return {
        isNewUser: true,
        registerToken: signRegisterToken({ mobileNumber: canonical }),
        user: null,
      };
    }

    const user = await prisma.user.update({
      where: { id: existing.id },
      data: { isMobileVerified: true, lastActiveAt: new Date() },
      include: { companion: true },
    });

    return { isNewUser: false, ...issueTokens(user), user: publicUser(user) };
  }

  // --- Google sign-in (email identity) -----------------------------------
  const email = String(decoded.email || '').trim().toLowerCase();
  if (!email) {
    throw ApiError.badRequest('This sign-in token has no email or phone number.');
  }

  const existing = await prisma.user.findUnique({
    where: { email },
    include: { companion: true },
  });

  if (!existing) {
    return {
      isNewUser: true,
      registerToken: signRegisterToken({
        email,
        fullName: decoded.name || null,
        profilePhotoUrl: decoded.picture || null,
      }),
      user: null,
    };
  }

  const user = await prisma.user.update({
    where: { id: existing.id },
    data: { lastActiveAt: new Date() },
    include: { companion: true },
  });

  return { isNewUser: false, ...issueTokens(user), user: publicUser(user) };
}

/**
 * Log in / sign up from a verified Google profile (the OAuth Authorization Code
 * flow — see services/google-oauth.service.js). Keys the account by verified
 * `email`, mirroring the Google branch of loginWithFirebase so the rest of the
 * app (register, tokens) is unchanged.
 * @param {{email:string, name?:string|null, picture?:string|null}} profile
 * @returns {Promise<{isNewUser:boolean, accessToken?, refreshToken?, registerToken?, user?}>}
 */
export async function loginWithGoogleProfile({ email, name, picture }) {
  const normEmail = String(email || '').trim().toLowerCase();
  if (!normEmail) {
    throw ApiError.badRequest('Your Google account has no email.');
  }

  const existing = await prisma.user.findUnique({
    where: { email: normEmail },
    include: { companion: true },
  });

  if (!existing) {
    return {
      isNewUser: true,
      // Surfaced for the app to prefill the registration screen (the browser
      // flow never sees the Google profile directly — only the backend does).
      email: normEmail,
      fullName: name || null,
      registerToken: signRegisterToken({
        email: normEmail,
        fullName: name || null,
        profilePhotoUrl: picture || null,
      }),
      user: null,
    };
  }

  const user = await prisma.user.update({
    where: { id: existing.id },
    data: { lastActiveAt: new Date() },
    include: { companion: true },
  });

  return { isNewUser: false, ...issueTokens(user), user: publicUser(user) };
}

/**
 * Google sign-in via Supabase Auth: verify the Supabase session JWT (JWKS),
 * then log the user in / start registration. Supabase is only the identity
 * source — the rest of the app runs on our own tokens.
 *  - existing user → issue app tokens (also backfills the supabaseUserId link
 *    on first Google login for a pre-existing email account);
 *  - new user → isNewUser=true + a register token carrying the Google identity,
 *    plus `prefill` so the client can pre-populate the profile screen.
 * @param {string} supabaseToken  the Supabase session access_token
 * @returns {{isNewUser:boolean, accessToken?, refreshToken?, registerToken?, prefill?, user?}}
 */
export async function loginWithSupabase(supabaseToken) {
  const identity = await verifySupabaseToken(supabaseToken);

  if (!identity.email) {
    throw ApiError.badRequest('Your Google account did not share an email address.');
  }
  const normEmail = String(identity.email).trim().toLowerCase();

  // Match an existing account by Supabase id first, then by verified email.
  let user = await prisma.user.findUnique({
    where: { supabaseUserId: identity.supabaseUserId },
    include: { companion: true },
  });
  if (!user) {
    user = await prisma.user.findUnique({
      where: { email: normEmail },
      include: { companion: true },
    });
  }

  if (user) {
    if (user.isBlocked) {
      throw ApiError.forbidden(user.blockedReason || 'Account is blocked');
    }
    // Backfill the OAuth link on first Google login for a pre-existing account.
    user = await prisma.user.update({
      where: { id: user.id },
      data: {
        supabaseUserId: identity.supabaseUserId,
        authProvider: user.authProvider || identity.provider || 'google',
        profilePhotoUrl: user.profilePhotoUrl || identity.photoUrl || undefined,
        lastActiveAt: new Date(),
      },
      include: { companion: true },
    });

    return { isNewUser: false, ...issueTokens(user), user: publicUser(user) };
  }

  return {
    isNewUser: true,
    registerToken: signRegisterToken({
      email: normEmail,
      fullName: identity.fullName || null,
      profilePhotoUrl: identity.photoUrl || null,
      supabaseUserId: identity.supabaseUserId,
      authProvider: identity.provider || 'google',
    }),
    prefill: {
      fullName: identity.fullName,
      email: normEmail,
      photoUrl: identity.photoUrl,
    },
    user: null,
  };
}

/**
 * Complete registration for a freshly verified identity (phone OR Google email).
 * Enforces age >= MIN_AGE (server-side, from dateOfBirth), creates the user + wallet,
 * links referral, and (for COMPANION role) creates the companions row (PENDING).
 * @param {object|string} identity  trusted identity from the verified register token:
 *                                  { mobileNumber?, email?, fullName?, profilePhotoUrl? }
 *                                  (a bare string is treated as a mobile number)
 * @param {object} input            validated body
 * @returns {{accessToken, refreshToken, user}}
 */
export async function register(identity, input) {
  const id = typeof identity === 'string' ? { mobileNumber: identity } : (identity || {});
  const mobileNumber = id.mobileNumber || null;
  const { fullName, gender, dateOfBirth, city, role, referralCode } = input;
  // Public @handle — validated + lowercased by the schema; normalise defensively.
  const username = String(input.username || '').trim().toLowerCase() || null;
  // Email: prefer the body, else the verified Google identity from the token.
  const email = String(input.email || id.email || '').trim().toLowerCase() || null;
  const profilePhotoUrl = id.profilePhotoUrl || null;

  // 18+ enforcement — computed server-side, never trusted from the client.
  const age = computeAge(dateOfBirth);
  if (!Number.isFinite(age) || age < config.business.minAge) {
    throw ApiError.badRequest(
      `You must be at least ${config.business.minAge} years old to use Companion Ranchi.`,
    );
  }

  // Identity must not already be registered (race-safe via unique constraints below).
  if (mobileNumber) {
    const existing = await prisma.user.findUnique({
      where: { mobileNumber },
      select: { id: true },
    });
    if (existing) {
      throw ApiError.conflict('This mobile number is already registered. Please log in.');
    }
  }

  if (email) {
    const emailTaken = await prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });
    if (emailTaken) throw ApiError.conflict('This email is already registered. Please log in.');
  }

  if (username) {
    const usernameTaken = await prisma.user.findUnique({
      where: { username },
      select: { id: true },
    });
    if (usernameTaken) {
      throw ApiError.conflict('That username is already taken. Please pick another.');
    }
  }

  // Resolve referrer (optional). An unknown code is ignored rather than failing signup.
  let referrer = null;
  if (referralCode) {
    referrer = await prisma.user.findUnique({
      where: { referralCode: referralCode.toUpperCase() },
      select: { id: true },
    });
  }

  const newReferralCode = await generateUniqueReferralCode();

  const created = await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        mobileNumber: mobileNumber || undefined, // null/omitted for Google sign-ups
        fullName,
        gender,
        dateOfBirth: new Date(dateOfBirth),
        city,
        email: email || undefined,
        username: username || undefined,
        profilePhotoUrl: profilePhotoUrl || undefined,
        supabaseUserId: id.supabaseUserId || undefined,
        authProvider: id.authProvider || (id.email ? 'google' : undefined),
        role,
        isMobileVerified: Boolean(mobileNumber),
        referralCode: newReferralCode,
        referredById: referrer ? referrer.id : undefined,
        lastActiveAt: new Date(),
      },
    });

    // Every user gets a wallet (customers hold referral/refund credit).
    await tx.wallet.create({ data: { userId: user.id } });

    // Link the referral as PENDING; reward is paid on the referee's first completed booking.
    if (referrer) {
      await tx.referral.create({
        data: {
          referrerId: referrer.id,
          referredId: user.id,
          status: 'PENDING',
          rewardAmount: config.business.referralReward,
        },
      });
    }

    // COMPANION onboarding starts in PENDING; goes live only after approval + KYC.
    if (role === 'COMPANION') {
      await tx.companion.create({
        data: {
          userId: user.id,
          city,
          status: 'PENDING',
        },
      });
    }

    return tx.user.findUnique({
      where: { id: user.id },
      include: { companion: true },
    });
  });

  return {
    ...issueTokens(created),
    user: publicUser(created),
  };
}

/**
 * Rotate refresh + access tokens. Verifies the refresh token, re-loads the user,
 * and issues a fresh pair.
 * @returns {{accessToken, refreshToken}}
 */
export async function refreshSession(refreshToken) {
  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch {
    throw ApiError.unauthorized('Invalid or expired refresh token');
  }

  const user = await prisma.user.findUnique({ where: { id: payload.sub } });
  if (!user) throw ApiError.unauthorized('User not found');
  if (user.isBlocked) throw ApiError.forbidden(user.blockedReason || 'Account is blocked');

  await prisma.user.update({
    where: { id: user.id },
    data: { lastActiveAt: new Date() },
  });

  return issueTokens(user);
}

/** Logout: clear the device fcmToken so pushes stop for this session. */
export async function logout(userId) {
  await prisma.user.update({
    where: { id: userId },
    data: { fcmToken: null, lastActiveAt: new Date() },
  });
  logger.debug(`[auth] user ${userId} logged out`);
  return { success: true };
}

/** Current session: the user plus companion profile when applicable. */
export async function getMe(userId) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { companion: true },
  });
  if (!user) throw ApiError.notFound('User not found');
  return publicUser(user);
}

/** Save / update the device FCM token for push delivery. */
export async function saveFcmToken(userId, fcmToken) {
  await prisma.user.update({
    where: { id: userId },
    data: { fcmToken, lastActiveAt: new Date() },
  });
  return { success: true };
}

/**
 * DEV/TEST ONLY: issue a REAL session for a demo account without an OTP, so the
 * app's offline "test login" (any number + 222222) gets a valid backend session
 * and authenticated screens work end-to-end. Falls back to the seeded demo
 * customer (+919000000001). Disabled when NODE_ENV=production.
 */
export async function devLogin(mobileNumber) {
  if (process.env.NODE_ENV === 'production') {
    throw ApiError.forbidden('Dev login is disabled in production.');
  }
  // Normalize to the canonical 10-digit form the rest of auth stores, so a
  // dev-login with a "+91…"/"0…" number still resolves the right account
  // (e.g. a seeded companion). Falls back to the seeded demo customer.
  const normalize = (v) =>
    String(v || '').replace(/\s|-/g, '').replace(/^\+?91/, '').replace(/^0/, '');
  const numbers = [];
  if (mobileNumber) {
    numbers.push(normalize(mobileNumber)); // canonical 10-digit
    numbers.push(String(mobileNumber).trim()); // raw, in case stored with +91
  }
  numbers.push('9000000001', '+919000000001'); // seeded demo customer (both forms)
  let user = null;
  for (const number of numbers) {
    if (!number) continue;
    user = await prisma.user.findUnique({
      where: { mobileNumber: number },
      include: { companion: true },
    });
    if (user) break;
  }
  if (!user) {
    throw ApiError.notFound('Demo user not found. Run `npm run seed` first.');
  }
  await prisma.user.update({
    where: { id: user.id },
    data: { isMobileVerified: true, lastActiveAt: new Date() },
  });
  return { isNewUser: false, ...issueTokens(user), user: publicUser(user) };
}

export default {
  requestOtp,
  verifyOtp,
  loginWithFirebase,
  loginWithSupabase,
  register,
  refreshSession,
  logout,
  getMe,
  saveFcmToken,
  verifyRegisterToken,
  computeAge,
  publicUser,
  publicCompanion,
  devLogin,
};
