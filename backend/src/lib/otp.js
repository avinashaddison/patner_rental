// OTP generation, hashing, comparison and delivery.
// In dev (OTP_CONSOLE=true) the OTP is logged and no SMS provider is contacted.
// In prod it is sent through MSG91 (India).
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { config } from '../config/index.js';
import { logger } from './logger.js';

/** Generate a numeric OTP of configured length. */
export function generateOtp() {
  const len = config.otp.length;
  const max = 10 ** len;
  // crypto.randomInt is upper-bound exclusive; pad to fixed length.
  const n = crypto.randomInt(0, max);
  return String(n).padStart(len, '0');
}

/** Hash an OTP for at-rest storage. */
export async function hashOtp(otp) {
  return bcrypt.hash(String(otp), 10);
}

/** Compare a plaintext OTP against a stored hash. */
export async function compareOtp(otp, hash) {
  if (!hash) return false;
  return bcrypt.compare(String(otp), hash);
}

/**
 * Deliver an OTP to a mobile number.
 * Dev: log to console. Prod: MSG91 transactional SMS.
 */
export async function sendOtpSms(mobile, otp) {
  if (config.otp.console) {
    logger.info(`[OTP] ${mobile} -> ${otp} (console mode; no SMS sent)`);
    return { delivered: true, channel: 'console' };
  }

  const { authKey, senderId, templateId } = config.otp.msg91;
  if (!authKey) {
    logger.warn(`[OTP] MSG91 not configured; OTP for ${mobile} not delivered.`);
    return { delivered: false, channel: 'none' };
  }

  try {
    const res = await fetch('https://control.msg91.com/api/v5/otp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        authkey: authKey,
      },
      body: JSON.stringify({
        template_id: templateId,
        mobile: mobile.replace(/^\+?/, '').replace(/^0+/, ''),
        sender: senderId,
        otp,
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      logger.error(`[OTP] MSG91 send failed for ${mobile}:`, data);
      return { delivered: false, channel: 'msg91', error: data };
    }
    return { delivered: true, channel: 'msg91' };
  } catch (err) {
    logger.error(`[OTP] MSG91 error for ${mobile}:`, err.message);
    return { delivered: false, channel: 'msg91', error: err.message };
  }
}

export default { generateOtp, hashOtp, compareOtp, sendOtpSms };
