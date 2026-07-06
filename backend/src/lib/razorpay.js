// Razorpay integration: order creation, payment + webhook signature verification, refunds.
// Lazily instantiates the SDK client so the app boots even with placeholder keys.
import crypto from 'crypto';
import Razorpay from 'razorpay';
import { config } from '../config/index.js';
import { logger } from './logger.js';

let client = null;

function getClient() {
  if (!client) {
    client = new Razorpay({
      key_id: config.razorpay.keyId,
      key_secret: config.razorpay.keySecret,
    });
  }
  return client;
}

/**
 * Create a Razorpay order.
 * @param {{amount:number, receipt:string, notes?:object}} args  amount in INR (rupees)
 * @returns {Promise<{id, amount, currency, receipt, status}>}
 */
export async function createOrder({ amount, receipt, notes = {} }) {
  const amountPaise = Math.round(Number(amount) * 100);
  const order = await getClient().orders.create({
    amount: amountPaise,
    currency: 'INR',
    receipt,
    notes,
    payment_capture: 1,
  });
  return order;
}

/**
 * Verify the signature returned by Razorpay Checkout after a successful payment.
 * @returns {boolean}
 */
export function verifyPaymentSignature({ orderId, paymentId, signature }) {
  const expected = crypto
    .createHmac('sha256', config.razorpay.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(String(signature || '')));
  } catch {
    return false;
  }
}

/**
 * Verify a Razorpay webhook signature against the raw request body.
 * @param {Buffer|string} rawBody  the exact bytes Razorpay sent
 * @param {string} signature  value of the X-Razorpay-Signature header
 * @returns {boolean}
 */
export function verifyWebhookSignature(rawBody, signature) {
  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody || ''));
  const expected = crypto
    .createHmac('sha256', config.razorpay.webhookSecret)
    .update(body)
    .digest('hex');
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(String(signature || '')));
  } catch {
    return false;
  }
}

/**
 * Refund a captured payment, optionally partial.
 * @param {string} paymentId
 * @param {number} [amount]  INR rupees; omit for full refund
 */
export async function refundPayment(paymentId, amount) {
  try {
    const payload = {};
    if (amount != null) payload.amount = Math.round(Number(amount) * 100);
    const refund = await getClient().payments.refund(paymentId, payload);
    return refund;
  } catch (err) {
    logger.error(`[Razorpay] refund failed for ${paymentId}:`, err?.error || err?.message || err);
    throw err;
  }
}

export default {
  createOrder,
  verifyPaymentSignature,
  verifyWebhookSignature,
  refundPayment,
};
