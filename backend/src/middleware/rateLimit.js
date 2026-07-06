// Rate limiters. otpLimiter guards OTP request/verify; apiLimiter is the global cap.
import rateLimit from 'express-rate-limit';

function handler(_req, res) {
  res.status(429).json({
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many requests, please try again later.', details: [] },
  });
}

// Tight limit on OTP endpoints to prevent SMS abuse / brute force.
export const otpLimiter = rateLimit({
  windowMs: 10 * 60 * 1000, // 10 minutes
  max: 8,
  standardHeaders: true,
  legacyHeaders: false,
  handler,
});

// Generous global limit for the rest of the API.
export const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  handler,
});

export default { otpLimiter, apiLimiter };
