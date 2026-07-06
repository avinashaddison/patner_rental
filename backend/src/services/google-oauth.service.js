// Google OAuth 2.0 "Authorization Code" flow — the Firebase-free Google login.
//
// The mobile app opens `/auth/google/start` in an in-app browser. Google sends
// the user back to `/auth/google/callback?code=...`; we exchange that code for an
// ID token **server-side using the client secret** (so the secret never reaches
// the app), read the verified email/name/photo, then bounce back to the app's
// custom scheme with a one-time login code that the app trades for its session.
//
// State + one-time codes are kept in-memory with a short TTL. That's fine for a
// single backend instance (our current deployment); a multi-instance deployment
// would move these to Redis/DB.
import jwt from 'jsonwebtoken';
import { customAlphabet } from 'nanoid';
import { config } from '../config/index.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';

const tokenAlphabet =
  'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const stateGen = customAlphabet(tokenAlphabet, 32);
const codeGen = customAlphabet(tokenAlphabet, 40);

const STATE_TTL_MS = 10 * 60 * 1000; // CSRF state — 10 minutes
const LOGIN_CODE_TTL_MS = 5 * 60 * 1000; // one-time login code — 5 minutes

/** @type {Map<string, number>} state -> expiresAt(ms) */
const states = new Map();
/** @type {Map<string, {envelope: object, expiresAt: number}>} loginCode -> session */
const sessions = new Map();

function sweep() {
  const now = Date.now();
  for (const [k, exp] of states) if (exp < now) states.delete(k);
  for (const [k, v] of sessions) if (v.expiresAt < now) sessions.delete(k);
}

/** True when the server has both a client id and secret configured. */
export function isConfigured() {
  return config.googleOAuth.configured;
}

/** Mint + remember a CSRF state nonce for an outgoing consent redirect. */
export function createState() {
  sweep();
  const state = stateGen();
  states.set(state, Date.now() + STATE_TTL_MS);
  return state;
}

/** Validate (and burn) a state nonce returned on the callback. */
export function consumeState(state) {
  if (!state) return false;
  const exp = states.get(state);
  if (exp === undefined) return false;
  states.delete(state);
  return exp >= Date.now();
}

/** Build Google's consent URL for the authorization-code flow. */
export function buildConsentUrl(state) {
  const params = new URLSearchParams({
    client_id: config.googleOAuth.clientId,
    redirect_uri: config.googleOAuth.redirectUri,
    response_type: 'code',
    scope: 'openid email profile',
    access_type: 'online',
    include_granted_scopes: 'true',
    prompt: 'select_account',
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

/**
 * Exchange an authorization code for the user's verified Google profile.
 * The ID token comes straight from Google's token endpoint over TLS in response
 * to our client-secret-authenticated request, so it's trusted; we still sanity
 * check the audience / issuer / expiry / email_verified claims.
 * @returns {Promise<{email:string, name:string|null, picture:string|null, sub:string|null}>}
 */
export async function exchangeCodeForProfile(code) {
  const body = new URLSearchParams({
    code,
    client_id: config.googleOAuth.clientId,
    client_secret: config.googleOAuth.clientSecret,
    redirect_uri: config.googleOAuth.redirectUri,
    grant_type: 'authorization_code',
  });

  let resp;
  try {
    resp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
  } catch (err) {
    logger.error({ err }, 'Google token exchange request failed');
    throw ApiError.unauthorized('Could not reach Google to complete sign-in.');
  }

  if (!resp.ok) {
    // Do NOT log the response body — it can echo the code/secret.
    logger.warn({ status: resp.status }, 'Google token exchange rejected');
    throw ApiError.unauthorized('Google sign-in failed. Please try again.');
  }

  const data = await resp.json();
  const idToken = data.id_token;
  if (!idToken) throw ApiError.unauthorized('Google sign-in returned no identity.');

  const payload = jwt.decode(idToken);
  if (!payload || typeof payload !== 'object') {
    throw ApiError.unauthorized('Could not read your Google identity.');
  }

  const okAud = payload.aud === config.googleOAuth.clientId;
  const okIss =
    payload.iss === 'accounts.google.com' ||
    payload.iss === 'https://accounts.google.com';
  const okExp = typeof payload.exp === 'number' && payload.exp * 1000 > Date.now();
  if (!okAud || !okIss || !okExp) {
    throw ApiError.unauthorized('Google identity failed validation.');
  }

  const email = String(payload.email || '').trim().toLowerCase();
  if (!email || payload.email_verified === false) {
    throw ApiError.badRequest('Your Google account has no verified email.');
  }

  return {
    email,
    name: payload.name || null,
    picture: payload.picture || null,
    sub: payload.sub || null,
  };
}

/** Stash a freshly-minted session behind a one-time code for the app to claim. */
export function stashSession(envelope) {
  sweep();
  const code = codeGen();
  sessions.set(code, { envelope, expiresAt: Date.now() + LOGIN_CODE_TTL_MS });
  return code;
}

/** Claim (and burn) a stashed session by its one-time code. */
export function consumeSession(code) {
  sweep();
  if (!code) return null;
  const entry = sessions.get(code);
  if (!entry) return null;
  sessions.delete(code);
  if (entry.expiresAt < Date.now()) return null;
  return entry.envelope;
}
