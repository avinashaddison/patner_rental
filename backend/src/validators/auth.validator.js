// Zod request schemas for the auth module (docs/API.md section 1).
// Used with the shared validate() middleware which replaces req[source] with parsed data.
import { z } from 'zod';

// Indian mobile numbers. Accept an optional +91 / 0 prefix and normalize to the
// bare 10-digit form (leading 6-9). Stored canonically as the 10-digit number.
const mobileNumber = z
  .string({ required_error: 'mobileNumber is required' })
  .trim()
  .transform((v) => v.replace(/\s|-/g, ''))
  .refine((v) => /^(\+?91|0)?[6-9]\d{9}$/.test(v), {
    message: 'Enter a valid Indian mobile number',
  })
  .transform((v) => v.replace(/^\+?91/, '').replace(/^0/, ''));

export const otpRequestSchema = z.object({
  mobileNumber,
});

export const otpVerifySchema = z.object({
  mobileNumber,
  otp: z
    .string({ required_error: 'otp is required' })
    .trim()
    .regex(/^\d{4,8}$/, 'Enter the OTP sent to your mobile'),
});

// Public @handle: 3-20 chars, lowercase letters/digits/underscore. Stored lowercase.
const username = z
  .string({ required_error: 'Username is required' })
  .trim()
  .toLowerCase()
  .min(3, 'Username must be at least 3 characters')
  .max(20, 'Username must be at most 20 characters')
  .regex(/^[a-z0-9_]+$/, 'Use lowercase letters, numbers and underscores only');

export const registerSchema = z.object({
  fullName: z.string().trim().min(2, 'Full name is too short').max(80),
  username,
  gender: z.enum(['MALE', 'FEMALE', 'OTHER'], {
    errorMap: () => ({ message: 'gender must be MALE, FEMALE or OTHER' }),
  }),
  // Accept a date or ISO datetime string; coerce to a Date. Age is validated in the service.
  dateOfBirth: z
    .string({ required_error: 'dateOfBirth is required' })
    .trim()
    .refine((v) => !Number.isNaN(Date.parse(v)), { message: 'dateOfBirth must be a valid date' }),
  city: z.string().trim().min(2).max(60),
  role: z.enum(['CUSTOMER', 'COMPANION'], {
    errorMap: () => ({ message: 'role must be CUSTOMER or COMPANION' }),
  }),
  referralCode: z.string().trim().min(4).max(24).optional(),
  email: z.string().trim().toLowerCase().email('Enter a valid email').optional(),
});

export const firebaseLoginSchema = z.object({
  idToken: z
    .string({ required_error: 'idToken is required' })
    .trim()
    .min(20, 'Invalid sign-in token'),
});

// Google login via Supabase Auth: the app exchanges its Supabase session token
// for our own JWTs (POST /auth/supabase).
export const supabaseLoginSchema = z.object({
  supabaseToken: z
    .string({ required_error: 'supabaseToken is required' })
    .trim()
    .min(20, 'A valid Supabase token is required'),
});

// Google OAuth code flow: the app trades the one-time login code (handed back on
// the deep link after sign-in) for the session envelope.
export const googleExchangeSchema = z.object({
  code: z.string({ required_error: 'code is required' }).trim().min(8, 'Invalid sign-in code'),
});

// Live username availability check (GET /auth/username-available?username=...).
// Lenient here (any non-empty string); format + availability decided in the service.
export const usernameQuerySchema = z.object({
  username: z.string({ required_error: 'username is required' }).trim().min(1).max(40),
});

export const refreshSchema = z.object({
  refreshToken: z.string({ required_error: 'refreshToken is required' }).trim().min(10),
});

export const fcmTokenSchema = z.object({
  fcmToken: z.string({ required_error: 'fcmToken is required' }).trim().min(8),
});

export default {
  otpRequestSchema,
  otpVerifySchema,
  firebaseLoginSchema,
  supabaseLoginSchema,
  googleExchangeSchema,
  usernameQuerySchema,
  registerSchema,
  refreshSchema,
  fcmTokenSchema,
};
