// Payments business logic: Razorpay order creation, checkout verification, capture,
// booking confirmation, and idempotent webhook handling (capture + refund).
//
// SECURITY: the chargeable amount is ALWAYS derived from the booking row, never from
// the client. The Payment.amount is the single source of truth for what was charged.
import pkg from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import {
  createOrder,
  verifyPaymentSignature,
  verifyWebhookSignature,
} from '../lib/razorpay.js';
import {
  isUpiGatewayConfigured,
  createUpiOrder,
  checkUpiOrderStatus,
} from '../lib/upigateway.js';
import { config } from '../config/index.js';
import { logger } from '../lib/logger.js';
import { ApiError } from '../utils/apiResponse.js';
import { round2, refundToCustomer } from './ledger.service.js';
import { notify } from './notification.service.js';
import { isPaymentMethodEnabled, getUpiReceiving } from './settings.service.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

/**
 * Recent bank credits seen by the mail watcher, keyed by UTR. Lets a customer
 * confirm a QR payment by typing the UTR from their UPI app even if the
 * amount-based auto-match missed (e.g. they paid a rounded amount). In-memory
 * and time-bounded — a restart just falls back to email/amount matching.
 */
const recentCredits = new Map(); // utr -> { amount, receivedAt(ms) }
const CREDIT_TTL_MS = 60 * 60_000; // keep an hour of history

function rememberCredit(utr, amount) {
  if (!utr) return;
  recentCredits.set(String(utr), { amount: Number(amount), receivedAt: Date.now() });
  // Prune anything older than the TTL so the map can't grow unbounded.
  const cutoff = Date.now() - CREDIT_TTL_MS;
  for (const [k, v] of recentCredits) {
    if (v.receivedAt < cutoff) recentCredits.delete(k);
  }
}

/** Statuses for which paying makes sense. */
const PAYABLE_BOOKING_STATUSES = new Set(['PENDING', 'CONFIRMED']);

/** Load a booking the caller owns (customer) or throw. */
async function getOwnedBooking(bookingId, customerId) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { payment: true, companion: { include: { user: true } } },
  });
  if (!booking) throw ApiError.notFound('Booking not found');
  if (booking.customerId !== customerId) {
    throw ApiError.forbidden('You can only pay for your own bookings');
  }
  return booking;
}

/**
 * Create (or return the existing) Razorpay order for a booking and ensure a
 * Payment row exists in CREATED state. Idempotent: re-calling returns the same order.
 * @returns {{razorpayOrderId, amount, currency, keyId, bookingId, status}}
 */
export async function createOrderForBooking(bookingId, customerId) {
  const booking = await getOwnedBooking(bookingId, customerId);

  if (!PAYABLE_BOOKING_STATUSES.has(booking.status)) {
    throw ApiError.conflict(`Booking in status ${booking.status} cannot be paid`);
  }

  const existing = booking.payment;
  if (existing && existing.status === 'CAPTURED') {
    throw ApiError.conflict('Booking is already paid');
  }
  if (existing && existing.method === 'cash') {
    throw ApiError.conflict('This is a cash (pay-in-person) booking; no online payment is needed.');
  }

  // Amount is derived from the booking — never trust the client.
  const amount = round2(booking.totalAmount);
  if (amount.lte(0)) throw ApiError.badRequest('Booking has no payable amount');

  // Reuse an existing CREATED order if one is already attached.
  if (existing && existing.razorpayOrderId && existing.status === 'CREATED') {
    return {
      razorpayOrderId: existing.razorpayOrderId,
      amount: Number(amount),
      currency: existing.currency || 'INR',
      keyId: config.razorpay.keyId,
      bookingId: booking.id,
      status: existing.status,
    };
  }

  let order;
  try {
    order = await createOrder({
      amount: Number(amount),
      receipt: booking.bookingCode,
      notes: {
        bookingId: booking.id,
        bookingCode: booking.bookingCode,
        customerId,
      },
    });
  } catch (err) {
    logger.error('[payments] createOrder failed:', err?.error || err?.message || err);
    throw ApiError.payment('Could not create payment order. Please try again.');
  }

  const payment = await prisma.payment.upsert({
    where: { bookingId: booking.id },
    create: {
      bookingId: booking.id,
      customerId,
      razorpayOrderId: order.id,
      amount,
      currency: 'INR',
      status: 'CREATED',
      method: 'razorpay',
    },
    update: {
      razorpayOrderId: order.id,
      amount,
      status: 'CREATED',
      razorpayPaymentId: null,
      razorpaySignature: null,
    },
  });

  return {
    razorpayOrderId: payment.razorpayOrderId,
    amount: Number(amount),
    currency: payment.currency,
    keyId: config.razorpay.keyId,
    bookingId: booking.id,
    status: payment.status,
  };
}

/**
 * Mark a booking CONFIRMED + payment CAPTURED inside one transaction, append status
 * history, and return the fresh booking. Idempotent on already-captured payments.
 */
async function markPaidAndConfirm({ payment, razorpayPaymentId, razorpaySignature, changedById }) {
  return prisma.$transaction(async (tx) => {
    const fresh = await tx.payment.findUnique({
      where: { id: payment.id },
      include: { booking: true },
    });
    if (!fresh) throw ApiError.notFound('Payment not found');

    // Idempotency guard: if already captured, do nothing further.
    const alreadyCaptured = fresh.status === 'CAPTURED';

    const updatedPayment = alreadyCaptured
      ? fresh
      : await tx.payment.update({
          where: { id: fresh.id },
          data: {
            status: 'CAPTURED',
            razorpayPaymentId: razorpayPaymentId ?? fresh.razorpayPaymentId,
            razorpaySignature: razorpaySignature ?? fresh.razorpaySignature,
            capturedAt: new Date(),
          },
        });

    let updatedBooking = fresh.booking;
    // Only advance a still-payable booking to CONFIRMED (don't clobber later states).
    if (!alreadyCaptured && PAYABLE_BOOKING_STATUSES.has(fresh.booking.status)) {
      updatedBooking = await tx.booking.update({
        where: { id: fresh.booking.id },
        data: { status: 'CONFIRMED' },
      });
      await tx.bookingStatusHistory.create({
        data: {
          bookingId: fresh.booking.id,
          status: 'CONFIRMED',
          changedById: changedById ?? null,
          note: 'Payment captured',
        },
      });
    }

    return { payment: updatedPayment, booking: updatedBooking, wasAlreadyCaptured: alreadyCaptured };
  });
}

/** Notify both parties that a booking is confirmed + paid. Best-effort. */
async function notifyConfirmed(booking) {
  try {
    const companion = await prisma.companion.findUnique({
      where: { id: booking.companionId },
      select: { userId: true },
    });
    await notify(booking.customerId, {
      type: 'PAYMENT',
      title: 'Payment successful',
      body: `Your booking ${booking.bookingCode} is confirmed.`,
      data: { bookingId: booking.id, bookingCode: booking.bookingCode },
    });
    if (companion?.userId) {
      await notify(companion.userId, {
        type: 'BOOKING',
        title: 'New confirmed booking',
        body: `Booking ${booking.bookingCode} has been paid and confirmed.`,
        data: { bookingId: booking.id, bookingCode: booking.bookingCode },
      });
    }
  } catch (err) {
    logger.debug(`[payments] confirm notify skipped: ${err.message}`);
  }
}

/**
 * Verify a Razorpay checkout signature, capture the payment, confirm the booking.
 * @returns {{payment, booking}}
 */
export async function verifyAndCapture({ razorpayOrderId, razorpayPaymentId, razorpaySignature }, customerId) {
  const payment = await prisma.payment.findFirst({
    where: { razorpayOrderId },
    include: { booking: true },
  });
  if (!payment) throw ApiError.notFound('Payment order not found');
  if (payment.customerId !== customerId) {
    throw ApiError.forbidden('You can only verify your own payments');
  }

  const valid = verifyPaymentSignature({
    orderId: razorpayOrderId,
    paymentId: razorpayPaymentId,
    signature: razorpaySignature,
  });
  if (!valid) {
    // Record the failure (only if not already captured) for auditability.
    if (payment.status !== 'CAPTURED') {
      await prisma.payment.update({
        where: { id: payment.id },
        data: { status: 'FAILED', razorpayPaymentId, razorpaySignature },
      });
    }
    throw ApiError.payment('Invalid payment signature');
  }

  const result = await markPaidAndConfirm({
    payment,
    razorpayPaymentId,
    razorpaySignature,
    changedById: customerId,
  });

  if (!result.wasAlreadyCaptured) {
    await notifyConfirmed(result.booking);
  }

  return { payment: result.payment, booking: result.booking };
}

/**
 * Handle a Razorpay webhook. Verifies the signature against the raw body, then
 * processes payment.captured + refund events idempotently.
 * @param {Buffer|string} rawBody  the exact bytes Razorpay sent
 * @param {string} signature  X-Razorpay-Signature header
 * @returns {{handled:boolean, event?:string}}
 */
export async function handleWebhook(rawBody, signature) {
  const valid = verifyWebhookSignature(rawBody, signature);
  if (!valid) throw ApiError.unauthorized('Invalid webhook signature');

  let event;
  try {
    const text = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');
    event = JSON.parse(text);
  } catch {
    throw ApiError.badRequest('Malformed webhook payload');
  }

  const type = event?.event;
  switch (type) {
    case 'payment.captured':
    case 'order.paid':
      await onPaymentCaptured(event);
      break;
    case 'payment.failed':
      await onPaymentFailed(event);
      break;
    case 'refund.created':
    case 'refund.processed':
      await onRefund(event);
      break;
    default:
      logger.debug(`[payments] webhook ignored event: ${type}`);
      return { handled: false, event: type };
  }

  return { handled: true, event: type };
}

/** Resolve the Payment for a webhook payload via orderId (preferred) or paymentId. */
async function resolvePaymentFromEvent(event) {
  const paymentEntity =
    event?.payload?.payment?.entity || event?.payload?.refund?.entity || {};
  const orderEntity = event?.payload?.order?.entity || {};
  const orderId = paymentEntity.order_id || orderEntity.id || null;
  const paymentId = paymentEntity.payment_id || paymentEntity.id || null;

  let payment = null;
  if (orderId) {
    payment = await prisma.payment.findFirst({
      where: { razorpayOrderId: orderId },
      include: { booking: true },
    });
  }
  if (!payment && paymentId) {
    payment = await prisma.payment.findFirst({
      where: { razorpayPaymentId: paymentId },
      include: { booking: true },
    });
  }
  return { payment, orderId, paymentId, paymentEntity };
}

/** Idempotent capture from webhook. */
async function onPaymentCaptured(event) {
  const { payment, paymentId } = await resolvePaymentFromEvent(event);
  if (!payment) {
    logger.warn('[payments] webhook capture for unknown order/payment');
    return;
  }
  if (payment.status === 'CAPTURED') return; // idempotent

  const result = await markPaidAndConfirm({
    payment,
    razorpayPaymentId: paymentId,
    razorpaySignature: payment.razorpaySignature,
    changedById: null,
  });

  if (!result.wasAlreadyCaptured) {
    await notifyConfirmed(result.booking);
  }
}

/** Mark a payment FAILED (idempotent; never downgrades a captured payment). */
async function onPaymentFailed(event) {
  const { payment, paymentId } = await resolvePaymentFromEvent(event);
  if (!payment) return;
  if (payment.status === 'CAPTURED' || payment.status === 'REFUNDED') return;
  if (payment.status === 'FAILED') return;

  await prisma.payment.update({
    where: { id: payment.id },
    data: { status: 'FAILED', razorpayPaymentId: paymentId ?? payment.razorpayPaymentId },
  });
}

/**
 * Idempotent refund handling. Marks payment REFUNDED, booking REFUNDED, credits the
 * customer's wallet via the ledger (refund fallback / source-of-truth ledger entry).
 */
async function onRefund(event) {
  const { payment } = await resolvePaymentFromEvent(event);
  if (!payment) {
    logger.warn('[payments] webhook refund for unknown payment');
    return;
  }
  if (payment.status === 'REFUNDED') return; // idempotent

  const booking = payment.booking;
  if (!booking) return;

  // refundToCustomer credits the wallet and sets payment.status=REFUNDED.
  await refundToCustomer(booking);

  await prisma.$transaction(async (tx) => {
    if (booking.status !== 'REFUNDED') {
      await tx.booking.update({ where: { id: booking.id }, data: { status: 'REFUNDED' } });
      await tx.bookingStatusHistory.create({
        data: { bookingId: booking.id, status: 'REFUNDED', note: 'Refund processed (webhook)' },
      });
    }
  });

  try {
    await notify(booking.customerId, {
      type: 'PAYMENT',
      title: 'Refund processed',
      body: `Your refund of ₹${Number(round2(booking.totalAmount))} for booking ${booking.bookingCode} has been processed.`,
      data: { bookingId: booking.id, bookingCode: booking.bookingCode },
    });
  } catch (err) {
    logger.debug(`[payments] refund notify skipped: ${err.message}`);
  }
}

/** Read the payment status for a booking the caller is party to. */
export async function getPaymentForBooking(bookingId, user) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { payment: true, companion: { select: { userId: true } } },
  });
  if (!booking) throw ApiError.notFound('Booking not found');

  const isCustomer = booking.customerId === user.id;
  const isCompanion = booking.companion?.userId === user.id;
  if (!isCustomer && !isCompanion && user.role !== 'ADMIN') {
    throw ApiError.forbidden('Not authorized to view this payment');
  }

  if (!booking.payment) {
    return {
      bookingId: booking.id,
      status: 'CREATED',
      amount: Number(round2(booking.totalAmount)),
      currency: 'INR',
      razorpayOrderId: null,
      razorpayPaymentId: null,
      capturedAt: null,
    };
  }

  const p = booking.payment;
  return {
    id: p.id,
    bookingId: booking.id,
    status: p.status,
    amount: Number(D(p.amount)),
    currency: p.currency,
    method: p.method,
    razorpayOrderId: p.razorpayOrderId,
    razorpayPaymentId: p.razorpayPaymentId,
    capturedAt: p.capturedAt,
    createdAt: p.createdAt,
  };
}

// ---------------------------------------------------------------------------
// UPIGateway (ekqr.in) — UPI QR payments.
//
// The Payment row's gateway-reference columns are reused for this provider:
//   razorpayOrderId   -> UPIGateway client_txn_id (our unique order reference)
//   razorpayPaymentId -> UPI transaction id / UTR (set on capture)
//   method            -> 'upigateway'
//
// SECURITY: UPIGateway webhooks are UNSIGNED form posts. We never trust the
// webhook body — every capture path re-verifies against check_order_status.
// ---------------------------------------------------------------------------

/**
 * Create a UPIGateway order for a booking and return the hosted payment URL.
 * A new client_txn_id is generated per call; the Payment row always tracks the
 * latest one (only that order can complete this booking's payment).
 */
export async function createUpiOrderForBooking(bookingId, customerId) {
  if (!isUpiGatewayConfigured()) {
    throw ApiError.payment('UPI payments are not configured');
  }
  if (!(await isPaymentMethodEnabled('upigateway'))) {
    throw ApiError.payment('UPI payment page is currently disabled');
  }

  const booking = await getOwnedBooking(bookingId, customerId);

  if (!PAYABLE_BOOKING_STATUSES.has(booking.status)) {
    throw ApiError.conflict(`Booking in status ${booking.status} cannot be paid`);
  }
  const existing = booking.payment;
  if (existing && existing.status === 'CAPTURED') {
    throw ApiError.conflict('Booking is already paid');
  }
  if (existing && existing.method === 'cash') {
    throw ApiError.conflict('This is a cash (pay-in-person) booking; no online payment is needed.');
  }

  const amount = round2(booking.totalAmount);
  if (amount.lte(0)) throw ApiError.badRequest('Booking has no payable amount');

  const customer = await prisma.user.findUnique({
    where: { id: customerId },
    select: { fullName: true, email: true, mobileNumber: true },
  });

  const clientTxnId = `${booking.bookingCode}-${Date.now().toString(36)}`;

  let order;
  try {
    order = await createUpiOrder({
      clientTxnId,
      amount: Number(amount),
      productInfo: `Booking ${booking.bookingCode}`,
      customerName: customer?.fullName || 'Customer',
      customerEmail: customer?.email || 'noreply@companionranchi.com',
      customerMobile: (customer?.mobileNumber || '').replace(/\D/g, '').slice(-10) || '9999999999',
      redirectUrl:
        config.upigateway.redirectUrl ||
        `${config.apiBaseUrl}/api/payments/upi/redirect`,
      udf1: booking.bookingCode,
    });
  } catch (err) {
    logger.error('[payments] upigateway createOrder failed:', err?.gateway || err?.message || err);
    throw ApiError.payment('Could not create UPI payment order. Please try again.');
  }

  const payment = await prisma.payment.upsert({
    where: { bookingId: booking.id },
    create: {
      bookingId: booking.id,
      customerId,
      razorpayOrderId: clientTxnId,
      amount,
      currency: 'INR',
      status: 'CREATED',
      method: 'upigateway',
    },
    update: {
      razorpayOrderId: clientTxnId,
      amount,
      status: 'CREATED',
      method: 'upigateway',
      razorpayPaymentId: null,
      razorpaySignature: null,
    },
  });

  return {
    clientTxnId,
    paymentUrl: order.paymentUrl,
    upiIntent: order.upiIntent || null,
    amount: Number(amount),
    currency: payment.currency,
    bookingId: booking.id,
    status: payment.status,
  };
}

/**
 * Query the gateway for the real status of a UPI payment and sync our row.
 * Used by both client polling and the webhook (which is untrusted on its own).
 * @returns {{payment, booking, gatewayStatus:string}}
 */
async function syncUpiPayment(payment) {
  const gw = await checkUpiOrderStatus(payment.razorpayOrderId, payment.createdAt);

  if (!gw.found) {
    return { payment, booking: payment.booking, gatewayStatus: 'not_found' };
  }

  if (gw.status === 'success') {
    // Amount must match what we charged (gateway deals in whole rupees).
    if (Math.round(Number(gw.amount)) !== Math.round(Number(payment.amount))) {
      logger.error(
        `[payments] upigateway amount mismatch for ${payment.razorpayOrderId}: gateway=${gw.amount} expected=${payment.amount}`,
      );
      return { payment, booking: payment.booking, gatewayStatus: 'amount_mismatch' };
    }
    const result = await markPaidAndConfirm({
      payment,
      razorpayPaymentId: gw.upiTxnId,
      razorpaySignature: null,
      changedById: null,
    });
    if (!result.wasAlreadyCaptured) {
      await notifyConfirmed(result.booking);
    }
    return { payment: result.payment, booking: result.booking, gatewayStatus: 'success' };
  }

  if (gw.status === 'failure') {
    if (payment.status !== 'CAPTURED' && payment.status !== 'REFUNDED' && payment.status !== 'FAILED') {
      await prisma.payment.update({
        where: { id: payment.id },
        data: { status: 'FAILED' },
      });
    }
    return { payment, booking: payment.booking, gatewayStatus: 'failure' };
  }

  // 'created' / 'scanning' — still pending at the gateway.
  return { payment, booking: payment.booking, gatewayStatus: gw.status || 'pending' };
}

/**
 * Client polling: check + capture a UPI payment the caller owns.
 * Safe to call repeatedly; capture is idempotent.
 */
export async function verifyUpiAndCapture(clientTxnId, customerId) {
  const payment = await prisma.payment.findFirst({
    where: { razorpayOrderId: clientTxnId, method: 'upigateway' },
    include: { booking: true },
  });
  if (!payment) throw ApiError.notFound('UPI payment order not found');
  if (payment.customerId !== customerId) {
    throw ApiError.forbidden('You can only verify your own payments');
  }

  const result = await syncUpiPayment(payment);
  return {
    bookingId: result.booking.id,
    bookingStatus: result.booking.status,
    paymentStatus: result.payment.status,
    gatewayStatus: result.gatewayStatus,
    upiTxnId: result.payment.razorpayPaymentId || null,
  };
}

/**
 * UPIGateway webhook (x-www-form-urlencoded, unsigned). The body is used only
 * to locate our payment; the actual state comes from check_order_status.
 */
export async function handleUpiWebhook(body) {
  const clientTxnId = body?.client_txn_id;
  if (!clientTxnId) {
    logger.warn('[payments] upigateway webhook without client_txn_id');
    return { handled: false };
  }

  const payment = await prisma.payment.findFirst({
    where: { razorpayOrderId: String(clientTxnId), method: 'upigateway' },
    include: { booking: true },
  });
  if (!payment) {
    logger.warn(`[payments] upigateway webhook for unknown order ${clientTxnId}`);
    return { handled: false };
  }
  if (payment.status === 'CAPTURED') return { handled: true, gatewayStatus: 'success' }; // idempotent

  const result = await syncUpiPayment(payment);
  return { handled: true, gatewayStatus: result.gatewayStatus };
}

// ---------------------------------------------------------------------------
// Self-hosted UPI QR ("upiqr") — dynamic QR to our own VPA, confirmed by the
// bank's credit-alert email (see lib/mailwatcher.js).
//
// Matching model: the bank email carries only amount + UTR + time (no order
// reference), so every pending QR gets a UNIQUE amount — booking total minus a
// 1–99 paise tag. One QR = one deposit:
//   - the paise tag is reserved while the QR is pending (expiry frees it)
//   - a UTR can only ever be recorded once (duplicate emails are ignored)
//
// Payment row reuse:  razorpayOrderId -> our QR reference (QR-<code>-<ts>)
//                     razorpayPaymentId -> bank UTR (set on capture)
//                     method -> 'upiqr'; amount -> the EXACT paise-tagged amount
// ---------------------------------------------------------------------------

/** Build a standard UPI deep link / QR payload. */
export function buildUpiIntent({ vpa, name, amount, note }) {
  const params = new URLSearchParams({
    pa: vpa,
    pn: name,
    am: Number(amount).toFixed(2),
    cu: 'INR',
    ...(note ? { tn: note.slice(0, 50) } : {}),
  });
  return `upi://pay?${params.toString()}`;
}

// After a QR "expires" for the customer, a payment can still land (they scanned
// late). We keep the paise tag RESERVED for this extra grace so it is never
// recycled onto a different booking while a late credit for the old amount is
// still possible — the whole amount-matching model depends on that uniqueness.
const SETTLEMENT_GRACE_MS = 10 * 60_000;

/** Orders created before this are fully dead: their paise tag may be reused. */
function qrExpiryDate() {
  return new Date(Date.now() - config.upiqr.expiryMin * 60_000);
}

/** Orders created before this are beyond even the settlement grace. */
function qrReserveSince() {
  return new Date(Date.now() - (config.upiqr.expiryMin * 60_000 + SETTLEMENT_GRACE_MS));
}

/**
 * A QR order can still be captured if it's live (CREATED) or expired only
 * recently (FAILED within the settlement grace) — a real credit for its exact
 * reserved amount is unambiguous. Beyond the grace the tag may be recycled, so
 * a stale order must never capture.
 */
function isQrCapturable(payment) {
  if (payment.status === 'CREATED') return true;
  if (payment.status === 'FAILED') {
    return new Date(payment.createdAt).getTime() >= qrReserveSince().getTime();
  }
  return false;
}

/**
 * Create (or refresh) a QR payment for a booking with a unique paise-tagged
 * amount. Returns everything the app needs to render the QR + intent button.
 */
export async function createQrOrderForBooking(bookingId, customerId) {
  // VPA is admin-controlled (settings `upi_vpa`) with UPIQR_VPA env fallback.
  const receiving = await getUpiReceiving();
  if (!receiving.vpa) {
    throw ApiError.payment('QR payments are not configured');
  }
  if (!(await isPaymentMethodEnabled('upiqr'))) {
    throw ApiError.payment('QR payments are currently disabled');
  }

  const booking = await getOwnedBooking(bookingId, customerId);
  if (!PAYABLE_BOOKING_STATUSES.has(booking.status)) {
    throw ApiError.conflict(`Booking in status ${booking.status} cannot be paid`);
  }
  const existing = booking.payment;
  if (existing && existing.status === 'CAPTURED') {
    throw ApiError.conflict('Booking is already paid');
  }
  if (existing && existing.method === 'cash') {
    throw ApiError.conflict('This is a cash (pay-in-person) booking; no online payment is needed.');
  }

  const base = round2(booking.totalAmount);
  if (base.lte(1)) throw ApiError.badRequest('Booking amount too small for QR payment');

  // Idempotency: if a still-live QR already exists for this booking, return it
  // unchanged. Minting a new tagged amount would orphan the QR the customer may
  // have already scanned (they'd pay the old amount and never match).
  if (
    existing &&
    existing.method === 'upiqr' &&
    existing.status === 'CREATED' &&
    new Date(existing.createdAt).getTime() >= qrExpiryDate().getTime()
  ) {
    const amt = round2(existing.amount);
    return {
      ref: existing.razorpayOrderId,
      upiIntent: buildUpiIntent({
        vpa: receiving.vpa,
        name: receiving.payeeName,
        amount: amt,
        note: booking.bookingCode,
      }),
      vpa: receiving.vpa,
      payeeName: receiving.payeeName,
      amount: Number(amt),
      currency: 'INR',
      bookingId: booking.id,
      status: existing.status,
      expiresAt: new Date(
        new Date(existing.createdAt).getTime() + config.upiqr.expiryMin * 60_000,
      ).toISOString(),
    };
  }

  const charged = await prisma.$transaction(
    async (tx) => {
      // Reserve a paise tag (1–99) unused by any order whose exact amount could
      // still receive a credit — i.e. live (CREATED) OR expired only within the
      // settlement grace (FAILED but tag not yet recyclable). Serializable so two
      // concurrent creations can't pick the same tag.
      const contenders = await tx.payment.findMany({
        where: {
          method: 'upiqr',
          status: { in: ['CREATED', 'FAILED'] },
          createdAt: { gte: qrReserveSince() },
          amount: { gt: base.minus(1), lte: base },
          ...(existing ? { id: { not: existing.id } } : {}),
        },
        select: { amount: true },
      });
      const used = new Set(
        contenders.map((p) => Math.round(base.minus(D(p.amount)).mul(100).toNumber())),
      );
      let tag = 0;
      for (let k = 1; k <= 99; k += 1) {
        if (!used.has(k)) {
          tag = k;
          break;
        }
      }
      if (!tag) {
        throw ApiError.conflict(
          'Too many pending QR payments right now. Try again in a few minutes.',
        );
      }

      const amt = round2(base.minus(D(tag).div(100)));
      const ref = `QR-${booking.bookingCode}-${Date.now().toString(36)}`;
      await tx.payment.upsert({
        where: { bookingId: booking.id },
        create: {
          bookingId: booking.id,
          customerId,
          razorpayOrderId: ref,
          amount: amt,
          currency: 'INR',
          status: 'CREATED',
          method: 'upiqr',
        },
        update: {
          razorpayOrderId: ref,
          amount: amt,
          status: 'CREATED',
          method: 'upiqr',
          razorpayPaymentId: null,
          razorpaySignature: null,
          createdAt: new Date(),
        },
      });
      return { amount: amt, ref };
    },
    { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
  );

  return {
    ref: charged.ref,
    upiIntent: buildUpiIntent({
      vpa: receiving.vpa,
      name: receiving.payeeName,
      amount: charged.amount,
      note: booking.bookingCode,
    }),
    vpa: receiving.vpa,
    payeeName: receiving.payeeName,
    amount: Number(charged.amount),
    currency: 'INR',
    bookingId: booking.id,
    status: 'CREATED',
    expiresAt: new Date(Date.now() + config.upiqr.expiryMin * 60_000).toISOString(),
  };
}

/** App polling: current state of a QR payment the caller owns. */
export async function verifyQrPayment(ref, customerId) {
  const payment = await prisma.payment.findFirst({
    where: { razorpayOrderId: ref, method: 'upiqr' },
    include: { booking: true },
  });
  if (!payment) throw ApiError.notFound('QR payment not found');
  if (payment.customerId !== customerId) {
    throw ApiError.forbidden('You can only check your own payments');
  }

  // Expire a stale pending QR on read so the paise tag frees up.
  if (payment.status === 'CREATED' && payment.createdAt < qrExpiryDate()) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED' } });
    return {
      bookingId: payment.booking.id,
      bookingStatus: payment.booking.status,
      paymentStatus: 'FAILED',
      gatewayStatus: 'expired',
      upiTxnId: null,
    };
  }

  return {
    bookingId: payment.booking.id,
    bookingStatus: payment.booking.status,
    paymentStatus: payment.status,
    gatewayStatus:
      payment.status === 'CAPTURED'
        ? 'success'
        : payment.status === 'FAILED'
          ? 'failure'
          : 'pending',
    upiTxnId: payment.razorpayPaymentId || null,
  };
}

/**
 * Called by the mail watcher for every parsed bank credit alert.
 * Matches amount -> pending QR order, guards UTR reuse, captures + confirms.
 * @returns {'captured'|'duplicate_utr'|'no_match'|'invalid'}
 */
export async function handleBankCredit({ amount, utr, receivedAt }) {
  const amt = Number(amount);
  if (!utr || !Number.isFinite(amt) || amt <= 0) return 'invalid';

  // Remember every credit so the manual "enter UTR" fallback can use it.
  rememberCredit(utr, amt);

  // One UTR = one deposit, ever.
  const seen = await prisma.payment.findFirst({
    where: { razorpayPaymentId: String(utr) },
    select: { id: true },
  });
  if (seen) {
    logger.debug(`[upiqr] duplicate UTR ${utr} ignored`);
    return 'duplicate_utr';
  }

  // Match the order whose EXACT reserved amount this credit paid. We include
  // recently-FAILED orders (expired within the settlement grace) because their
  // paise tag was never recycled, so the amount still maps to exactly one order
  // — this is how a genuine last-second payment still confirms. CREATED wins
  // over FAILED when both somehow exist ('CREATED' < 'FAILED').
  const payment = await prisma.payment.findFirst({
    where: {
      method: 'upiqr',
      status: { in: ['CREATED', 'FAILED'] },
      amount: amt,
      createdAt: { gte: qrReserveSince() },
    },
    orderBy: [{ status: 'asc' }, { createdAt: 'desc' }],
    include: { booking: true },
  });

  if (!payment || !isQrCapturable(payment)) {
    logger.warn(`[upiqr] unmatched bank credit: INR ${amt} UTR ${utr} at ${receivedAt || 'n/a'}`);
    return 'no_match';
  }

  try {
    const result = await markPaidAndConfirm({
      payment,
      razorpayPaymentId: String(utr),
      razorpaySignature: null,
      changedById: null,
    });
    if (!result.wasAlreadyCaptured) {
      await notifyConfirmed(result.booking);
    }
    logger.info(
      `[upiqr] captured INR ${amt} UTR ${utr} -> booking ${payment.booking.bookingCode}`,
    );
    return 'captured';
  } catch (err) {
    // Unique-index violation on the UTR = another path already captured it.
    if (err?.code === 'P2002') {
      logger.debug(`[upiqr] UTR ${utr} captured concurrently — treated as duplicate`);
      return 'duplicate_utr';
    }
    throw err;
  }
}

/**
 * Manual UTR fallback: the customer types the UTR shown in their UPI app and we
 * try to confirm the QR order with it.
 *   - if the order is already captured (auto-matched), report success
 *   - else, if that UTR was seen crediting our account (mail watcher) for at
 *     least the charged amount and isn't already used, capture with it
 *   - otherwise report 'not_found' so the UI can say "not received yet"
 * @returns {{bookingId, bookingStatus, paymentStatus, result:'captured'|'already'|'not_found'|'duplicate_utr'|'amount_short'}}
 */
export async function checkQrByUtr(ref, utr, customerId) {
  const cleanUtr = String(utr || '').replace(/\s+/g, '');
  const payment = await prisma.payment.findFirst({
    where: { razorpayOrderId: ref, method: 'upiqr' },
    include: { booking: true },
  });
  if (!payment) throw ApiError.notFound('QR payment not found');
  if (payment.customerId !== customerId) {
    throw ApiError.forbidden('You can only check your own payments');
  }

  const respond = (result) => ({
    bookingId: payment.booking.id,
    bookingStatus: payment.booking.status,
    paymentStatus: payment.status,
    result,
  });

  if (payment.status === 'CAPTURED') return respond('already');

  // Only a live or just-expired (within grace) order may be confirmed. A fully
  // stale order's paise tag may have been recycled, so its amount is ambiguous.
  if (!isQrCapturable(payment)) return respond('expired');

  // This UTR already settled another order — never double-credit.
  const usedElsewhere = await prisma.payment.findFirst({
    where: { razorpayPaymentId: cleanUtr, NOT: { id: payment.id } },
    select: { id: true },
  });
  if (usedElsewhere) return respond('duplicate_utr');

  const credit = recentCredits.get(cleanUtr);
  if (!credit) return respond('not_found');

  // The credit must be for THIS order's exact paise-tagged amount — the same
  // exactness as auto-matching. "≥ amount" would let an unrelated larger credit
  // (or another customer's payment) confirm this booking.
  if (Math.round(Number(credit.amount) * 100) !== Math.round(Number(payment.amount) * 100)) {
    return respond('amount_mismatch');
  }

  try {
    const result = await markPaidAndConfirm({
      payment,
      razorpayPaymentId: cleanUtr,
      razorpaySignature: null,
      changedById: customerId,
    });
    if (!result.wasAlreadyCaptured) {
      await notifyConfirmed(result.booking);
    }
    logger.info(`[upiqr] manual UTR ${cleanUtr} confirmed booking ${payment.booking.bookingCode}`);
    return {
      bookingId: result.booking.id,
      bookingStatus: result.booking.status,
      paymentStatus: result.payment.status,
      result: 'captured',
    };
  } catch (err) {
    if (err?.code === 'P2002') return respond('duplicate_utr');
    throw err;
  }
}

/** Periodic sweep: fail pending QR orders past their validity window. */
export async function expireStaleQrOrders() {
  const { count } = await prisma.payment.updateMany({
    where: { method: 'upiqr', status: 'CREATED', createdAt: { lt: qrExpiryDate() } },
    data: { status: 'FAILED' },
  });
  if (count > 0) logger.info(`[upiqr] expired ${count} stale QR order(s)`);
  return count;
}

export default {
  createOrderForBooking,
  verifyAndCapture,
  handleWebhook,
  getPaymentForBooking,
  createUpiOrderForBooking,
  verifyUpiAndCapture,
  handleUpiWebhook,
  buildUpiIntent,
  createQrOrderForBooking,
  verifyQrPayment,
  checkQrByUtr,
  handleBankCredit,
  expireStaleQrOrders,
};
