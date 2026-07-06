// Auth routes — auto-mounted at /api/auth. See docs/API.md section 1.
import { Router } from 'express';
import * as authController from '../controllers/auth.controller.js';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { otpLimiter } from '../middleware/rateLimit.js';
import {
  otpRequestSchema,
  otpVerifySchema,
  firebaseLoginSchema,
  supabaseLoginSchema,
  googleExchangeSchema,
  usernameQuerySchema,
  registerSchema,
  refreshSchema,
  fcmTokenSchema,
} from '../validators/auth.validator.js';

const router = Router();

// Public — OTP login flow (rate-limited to prevent SMS abuse / brute force).
router.post('/otp/request', otpLimiter, validate(otpRequestSchema), authController.requestOtp);
router.post('/otp/verify', otpLimiter, validate(otpVerifySchema), authController.verifyOtp);

// Public — Firebase Phone Auth: exchange a Firebase ID token for our session.
router.post('/firebase', otpLimiter, validate(firebaseLoginSchema), authController.firebaseLogin);

// Public — Google login via Supabase Auth: verify a Supabase-issued JWT (JWKS)
// and exchange it for our session. This is the flow the app's "Continue with
// Google" button uses (native picker → Supabase → here).
router.post('/supabase', otpLimiter, validate(supabaseLoginSchema), authController.supabaseLogin);

// Public — Google OAuth (Authorization Code) flow. No Firebase, no SHA-1: the app
// opens /google/start in an in-app browser, Google bounces to /google/callback,
// and the app trades the one-time code at /google/exchange for our session.
router.get('/google/start', otpLimiter, authController.googleStart);
router.get('/google/callback', authController.googleCallback);
router.post('/google/exchange', otpLimiter, validate(googleExchangeSchema), authController.googleExchange);

// Public — live @username availability check for the registration form.
router.get('/username-available', validate(usernameQuerySchema, 'query'), authController.usernameAvailable);

// Public — complete profile (requires temp token from verify; age >= 18 enforced in service).
router.post('/register', validate(registerSchema), authController.register);

// Public — token rotation.
router.post('/refresh', validate(refreshSchema), authController.refresh);

// Public — DEV/TEST ONLY: instant demo session (no OTP). Guarded in the service.
router.post('/dev-login', authController.devLogin);

// Authenticated.
router.post('/logout', requireAuth, authController.logout);
router.get('/me', requireAuth, authController.me);
router.post('/fcm-token', requireAuth, validate(fcmTokenSchema), authController.fcmToken);

export default router;
