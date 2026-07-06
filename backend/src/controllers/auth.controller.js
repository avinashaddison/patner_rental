// Thin HTTP handlers for /auth. Parse the request, call the service, send the envelope.
import * as authService from '../services/auth.service.js';
import * as googleOAuth from '../services/google-oauth.service.js';
import { config } from '../config/index.js';
import { ok, created, ApiError } from '../utils/apiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function bearerToken(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) return header.slice(7).trim();
  return null;
}

// POST /auth/otp/request
export const requestOtp = asyncHandler(async (req, res) => {
  const { mobileNumber } = req.body;
  const result = await authService.requestOtp(mobileNumber);
  return ok(res, result);
});

// POST /auth/otp/verify
export const verifyOtp = asyncHandler(async (req, res) => {
  const { mobileNumber, otp } = req.body;
  const result = await authService.verifyOtp(mobileNumber, otp);
  return ok(res, result);
});

// POST /auth/firebase — exchange a Firebase Phone Auth ID token for our session.
export const firebaseLogin = asyncHandler(async (req, res) => {
  const result = await authService.loginWithFirebase(req.body.idToken);
  return ok(res, result);
});

// POST /auth/supabase — log in / sign up with a Supabase-verified Google identity.
// Body: { supabaseToken }. Returns app tokens (existing user) or a register token
// + prefill (new user, to complete the profile via /auth/register).
export const supabaseLogin = asyncHandler(async (req, res) => {
  const result = await authService.loginWithSupabase(req.body.supabaseToken);
  return ok(res, result);
});

// GET /auth/google/start — open Google's consent page (in the app's in-app
// browser). We mint a CSRF state and redirect there.
export const googleStart = asyncHandler(async (req, res) => {
  if (!googleOAuth.isConfigured()) {
    throw ApiError.internal('Google sign-in is not configured on the server.');
  }
  const state = googleOAuth.createState();
  return res.redirect(googleOAuth.buildConsentUrl(state));
});

// GET /auth/google/callback — Google redirects here with ?code&state. We exchange
// the code server-side (with the client secret), create/link the user, stash the
// session behind a one-time code and bounce to the app's deep link. Errors bounce
// back too (with ?error) so the app's browser session always resolves.
export const googleCallback = asyncHandler(async (req, res) => {
  const scheme = config.googleOAuth.appScheme;
  const bounce = (params) =>
    res.redirect(`${scheme}://auth?${new URLSearchParams(params).toString()}`);

  const { code, state, error } = req.query;
  if (error) return bounce({ error: String(error) });
  if (!code || !googleOAuth.consumeState(String(state || ''))) {
    return bounce({ error: 'invalid_request' });
  }

  try {
    const profile = await googleOAuth.exchangeCodeForProfile(String(code));
    const envelope = await authService.loginWithGoogleProfile(profile);
    return bounce({ code: googleOAuth.stashSession(envelope) });
  } catch {
    return bounce({ error: 'signin_failed' });
  }
});

// POST /auth/google/exchange — the app trades the one-time login code for the
// session envelope (isNewUser, accessToken/refreshToken or registerToken, user).
export const googleExchange = asyncHandler(async (req, res) => {
  const envelope = googleOAuth.consumeSession(req.body.code);
  if (!envelope) {
    throw ApiError.unauthorized('Sign-in code is invalid or has expired. Please try again.');
  }
  return ok(res, envelope);
});

// GET /auth/username-available?username=... — live availability for the register form.
export const usernameAvailable = asyncHandler(async (req, res) => {
  const result = await authService.isUsernameAvailable(req.query.username);
  return ok(res, result);
});

// POST /auth/register — completes the profile for a freshly verified identity
// (Google email or phone). Requires the short-lived registration (temp) token
// issued by /auth/firebase (or the legacy /auth/otp/verify).
export const register = asyncHandler(async (req, res) => {
  const token = bearerToken(req);
  if (!token) {
    throw ApiError.unauthorized('Missing registration token. Please sign in first.');
  }

  let identity;
  try {
    identity = authService.verifyRegisterToken(token);
  } catch {
    throw ApiError.unauthorized('Invalid or expired registration token. Please sign in again.');
  }

  const result = await authService.register(identity, req.body);
  return created(res, result);
});

// POST /auth/refresh
export const refresh = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const tokens = await authService.refreshSession(refreshToken);
  return ok(res, tokens);
});

// POST /auth/logout
export const logout = asyncHandler(async (req, res) => {
  const result = await authService.logout(req.user.id);
  return ok(res, result);
});

// GET /auth/me
export const me = asyncHandler(async (req, res) => {
  const user = await authService.getMe(req.user.id);
  return ok(res, { user });
});

// POST /auth/fcm-token
export const fcmToken = asyncHandler(async (req, res) => {
  const result = await authService.saveFcmToken(req.user.id, req.body.fcmToken);
  return ok(res, result);
});

// POST /auth/dev-login — DEV/TEST ONLY: real demo session without OTP.
export const devLogin = asyncHandler(async (req, res) => {
  const result = await authService.devLogin(req.body && req.body.mobileNumber);
  return ok(res, result);
});

export default {
  requestOtp,
  verifyOtp,
  firebaseLogin,
  supabaseLogin,
  googleStart,
  googleCallback,
  googleExchange,
  usernameAvailable,
  register,
  refresh,
  logout,
  me,
  fcmToken,
  devLogin,
};
