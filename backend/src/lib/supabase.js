// Supabase Auth token verification.
// Verifies a Supabase-issued access token (JWT) against the project's JWKS,
// so we can trust the identity (email / sub) a mobile client obtained via
// Google sign-in through Supabase. On success we mint our OWN app tokens
// (see auth.service.loginWithSupabase) — Supabase is only the identity source.
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { config } from '../config/index.js';
import { logger } from './logger.js';
import { ApiError } from '../utils/apiResponse.js';

let jwks = null;

/** Lazily build (and cache) the remote JWKS. jose caches/rotates keys internally. */
function getJwks() {
  if (jwks) return jwks;
  const url = config.supabase.jwksUrl;
  if (!url) {
    // Server misconfiguration (our fault) — surfaces as 500, which is correct.
    throw ApiError.internal('Supabase auth is not configured (set SUPABASE_JWKS_URL or SUPABASE_URL).');
  }
  jwks = createRemoteJWKSet(new URL(url), {
    cooldownDuration: 30_000, // don't refetch keys more than every 30s on miss
  });
  return jwks;
}

/**
 * Verify a Supabase access token and return the normalized identity.
 * Throws on any invalid/expired/untrusted token.
 * @param {string} token  the Supabase session access_token (a JWT)
 * @returns {Promise<{supabaseUserId:string, email:string|null, emailVerified:boolean,
 *   fullName:string|null, photoUrl:string|null, provider:string|null}>}
 */
export async function verifySupabaseToken(token) {
  if (!token || typeof token !== 'string') {
    throw ApiError.unauthorized('Missing Supabase token');
  }

  const issuer = config.supabase.url
    ? `${config.supabase.url.replace(/\/$/, '')}/auth/v1`
    : undefined;

  let payload;
  try {
    ({ payload } = await jwtVerify(token, getJwks(), {
      audience: 'authenticated',
      ...(issuer ? { issuer } : {}),
    }));
  } catch (err) {
    logger.warn(`[supabase] token verification failed: ${err.message}`);
    // Common cause: project still on legacy HS256 JWT secret (JWKS is empty).
    // Enable asymmetric JWT signing keys in the Supabase dashboard.
    throw ApiError.unauthorized('Invalid or expired Supabase token');
  }

  const meta = payload.user_metadata || {};
  const email = (payload.email || meta.email || null);

  return {
    supabaseUserId: String(payload.sub),
    email: email ? String(email).toLowerCase() : null,
    emailVerified: Boolean(payload.email_verified ?? meta.email_verified ?? false),
    fullName: meta.full_name || meta.name || null,
    photoUrl: meta.avatar_url || meta.picture || null,
    provider: (payload.app_metadata && payload.app_metadata.provider) || meta.provider || 'google',
  };
}

export default { verifySupabaseToken };
