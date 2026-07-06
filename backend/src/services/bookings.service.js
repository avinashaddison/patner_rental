// Bookings engine: quoting, creation (with Razorpay order + payment row), role-aware
// listing, detail, and the full status machine
//   PENDING -> CONFIRMED -> IN_PROGRESS -> COMPLETED
//   (+ CANCELLED / REFUNDED on cancel/reject).
//
// Money math is the single source of truth from docs/DATA_MODEL.md:
//   totalAmount      = hourlyRate * durationHours
//   commissionAmount = round2(totalAmount * commissionRate / 100)
//   companionPayout  = totalAmount - commissionAmount
//
// On COMPLETED we credit the companion's payout, record platform commission, and
// evaluate the referral reward via the shared ledger service. Every transition writes
// a booking_status_history row and notifies the affected party.
import pkg from '@prisma/client';
import { customAlphabet } from 'nanoid';
import { prisma } from '../lib/prisma.js';
import { logger } from '../lib/logger.js';
import { ApiError } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import {
  getCommissionRate,
  isPaymentMethodEnabled,
  getEnabledPaymentMethods,
} from './settings.service.js';
import { notify } from './notification.service.js';
import { isKycApproved } from './companions.service.js';
import {
  round2,
  creditCompanionEarning,
  recordCommission,
  settleCashBooking,
  applyReferralRewardIfEligible,
  refundToCustomer,
} from './ledger.service.js';
import {
  BOOKING_DURATIONS,
  ALLOWED_PLACE_TYPES,
  ALLOWED_ACTIVITIES,
} from '../config/constants.js';
import { createOrder, refundPayment } from '../lib/razorpay.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

// Booking codes look like CR-7F3A2B (uppercase, no ambiguous chars).
const codeAlphabet = customAlphabet('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 6);
function generateBookingCode() {
  return `CR-${codeAlphabet()}`;
}

// Meet-at-location "start code": a 6-digit numeric OTP the customer shows the
// companion in person to begin the meetup. Numeric so it's easy to read aloud.
const startCodeDigits = customAlphabet('0123456789', 6);
function generateStartCode() {
  return startCodeDigits();
}

// How many wrong start-code entries before the companion is locked out (must
// contact support / let the customer cancel). Keeps a guessing attacker out.
const MAX_START_CODE_ATTEMPTS = 8;

// ---- time helpers ----------------------------------------------------------

/** "HH:mm" -> minutes since midnight. */
function timeToMinutes(hhmm) {
  const [h, m] = String(hhmm).split(':').map((n) => parseInt(n, 10));
  return h * 60 + m;
}

/** minutes since midnight -> "HH:mm" (wraps within a single day; clamps at 24:00). */
function minutesToTime(mins) {
  const clamped = Math.min(mins, 24 * 60);
  const h = Math.floor(clamped / 60);
  const m = clamped % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** Parse a YYYY-MM-DD string to a UTC midnight Date (matches @db.Date semantics). */
function parseBookingDate(ymd) {
  const [y, m, d] = ymd.split('-').map((n) => parseInt(n, 10));
  const date = new Date(Date.UTC(y, m - 1, d));
  if (Number.isNaN(date.getTime())) throw ApiError.badRequest('Invalid bookingDate');
  return date;
}

// ---- price math ------------------------------------------------------------

/**
 * Compute the booking price breakdown from a snapshot hourly rate + duration.
 * @returns {{hourlyRate, durationHours, totalAmount, commissionRate, commissionAmount, companionPayout, currency}}
 */
export function computeBreakdown({ hourlyRate, durationHours, commissionRate }) {
  const rate = round2(hourlyRate);
  const total = round2(rate.times(durationHours));
  const commissionAmount = round2(total.times(commissionRate).dividedBy(100));
  const companionPayout = round2(total.minus(commissionAmount));
  return {
    hourlyRate: rate.toNumber(),
    durationHours,
    totalAmount: total.toNumber(),
    commissionRate,
    commissionAmount: commissionAmount.toNumber(),
    companionPayout: companionPayout.toNumber(),
    currency: 'INR',
  };
}

/**
 * Price a prospective booking without writing anything.
 * @param {{companionId:string, durationHours:number}} input
 */
export async function quoteBooking({ companionId, durationHours }) {
  if (!BOOKING_DURATIONS.includes(durationHours)) {
    throw ApiError.badRequest(`durationHours must be one of ${BOOKING_DURATIONS.join(', ')}`);
  }
  const companion = await prisma.companion.findUnique({
    where: { id: companionId },
    include: { user: { select: { fullName: true } } },
  });
  if (!companion) throw ApiError.notFound('Companion not found');
  if (companion.status !== 'APPROVED') {
    throw ApiError.conflict('Companion is not available for booking');
  }
  // Safety contract (d): only fully KYC-verified companions are bookable. This
  // mirrors the discovery filter so an APPROVED-but-unverified companion can
  // never be booked directly by id.
  if (!(await isKycApproved(companion.userId))) {
    throw ApiError.conflict('Companion is not available for booking');
  }

  const commissionRate = await getCommissionRate();
  const breakdown = computeBreakdown({
    hourlyRate: companion.hourlyRate,
    durationHours,
    commissionRate,
  });

  return {
    companionId: companion.id,
    companionName: companion.user?.fullName ?? null,
    ...breakdown,
  };
}

// ---- availability ----------------------------------------------------------

/**
 * Verify a companion is free for [startTime, endTime] on bookingDate:
 *  - the day/time falls inside a weekly availability window (if any are defined), and
 *  - no existing active booking on that date overlaps the requested interval.
 * @throws ApiError.conflict when unavailable
 */
async function assertSlotAvailable({ companionId, bookingDate, startTime, endTime, client = prisma }) {
  const startMin = timeToMinutes(startTime);
  const endMin = timeToMinutes(endTime);

  // 1) Weekly recurring availability (only enforced if the companion configured any).
  const windows = await client.companionAvailability.findMany({
    where: { companionId, isAvailable: true },
  });
  if (windows.length > 0) {
    const dayOfWeek = bookingDate.getUTCDay(); // 0=Sun..6=Sat
    const fits = windows.some((w) => {
      if (w.dayOfWeek !== dayOfWeek) return false;
      return timeToMinutes(w.startTime) <= startMin && timeToMinutes(w.endTime) >= endMin;
    });
    if (!fits) {
      throw ApiError.conflict('Companion is not available at the requested time');
    }
  }

  // 2) Overlap with existing live bookings on the same date.
  const sameDay = await client.booking.findMany({
    where: {
      companionId,
      bookingDate,
      status: { in: ['PENDING', 'CONFIRMED', 'IN_PROGRESS'] },
    },
    select: { startTime: true, endTime: true },
  });
  const overlaps = sameDay.some((b) => {
    const bStart = timeToMinutes(b.startTime);
    const bEnd = timeToMinutes(b.endTime);
    return startMin < bEnd && endMin > bStart;
  });
  if (overlaps) {
    throw ApiError.conflict('That time slot is already booked');
  }
}

// ---- creation --------------------------------------------------------------

/**
 * Create a PENDING booking + a CREATED Payment with a Razorpay order, snapshotting
 * the rate + commission. Validates duration, companion approval, public meeting place,
 * companionship activity, slot availability, and block relationship.
 * @param {string} customerId
 * @param {object} input  validated body from createBookingSchema
 */
export async function createBooking(customerId, input) {
  const {
    companionId,
    categoryId,
    activity,
    durationHours,
    bookingDate: bookingDateRaw,
    startTime,
    meetingLocation,
    meetingPlaceType,
    notes,
    paymentMethod: paymentMethodRaw,
  } = input;

  // Payment intent at booking time is just cash vs online. For online we store a
  // default online rail; the customer picks the concrete one (UPI QR / UPI page /
  // card) on the payment screen afterwards, which updates Payment.method.
  // Preference order for the default online rail: UPI QR > UPI page > Razorpay.
  const wantsCash = paymentMethodRaw === 'cash';
  let paymentMethod;
  if (wantsCash) {
    if (!(await isPaymentMethodEnabled('cash'))) {
      throw ApiError.badRequest('Cash payment is not available right now.');
    }
    paymentMethod = 'cash';
  } else {
    const enabled = await getEnabledPaymentMethods();
    paymentMethod =
      (enabled.upiqr && 'upiqr') ||
      (enabled.upigateway && 'upigateway') ||
      (enabled.razorpay && 'razorpay') ||
      null;
    if (!paymentMethod) {
      throw ApiError.badRequest('Online payment is not available right now.');
    }
  }

  // Safety policy (defense-in-depth alongside zod).
  if (!BOOKING_DURATIONS.includes(durationHours)) {
    throw ApiError.badRequest(`durationHours must be one of ${BOOKING_DURATIONS.join(', ')}`);
  }
  if (!ALLOWED_PLACE_TYPES.includes(meetingPlaceType)) {
    throw ApiError.badRequest('Meetings are only allowed in public places');
  }
  if (!ALLOWED_ACTIVITIES.includes(activity)) {
    throw ApiError.badRequest('Only companionship activities are allowed');
  }

  const bookingDate = parseBookingDate(bookingDateRaw);
  const endTime = minutesToTime(timeToMinutes(startTime) + durationHours * 60);

  const companion = await prisma.companion.findUnique({
    where: { id: companionId },
    include: { user: { select: { id: true, fullName: true } } },
  });
  if (!companion) throw ApiError.notFound('Companion not found');
  if (companion.status !== 'APPROVED') {
    throw ApiError.conflict('Companion is not available for booking');
  }
  // Safety contract (d): block booking of a companion whose KYC isn't fully
  // approved, even if their status was set APPROVED. Mirrors discovery gating.
  if (!(await isKycApproved(companion.userId))) {
    throw ApiError.conflict('Companion is not available for booking');
  }
  if (companion.userId === customerId) {
    throw ApiError.badRequest('You cannot book yourself');
  }

  // Either party blocking the other prevents booking.
  const block = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: customerId, blockedId: companion.userId },
        { blockerId: companion.userId, blockedId: customerId },
      ],
    },
  });
  if (block) throw ApiError.forbidden('Booking is not allowed between these users');

  // Optional category must exist and be active.
  if (categoryId) {
    const category = await prisma.category.findUnique({ where: { id: categoryId } });
    if (!category || !category.isActive) throw ApiError.badRequest('Invalid category');
  }

  await assertSlotAvailable({ companionId, bookingDate, startTime, endTime });

  const commissionRate = await getCommissionRate();
  const breakdown = computeBreakdown({
    hourlyRate: companion.hourlyRate,
    durationHours,
    commissionRate,
  });

  if (breakdown.totalAmount <= 0) {
    throw ApiError.conflict('Companion has not set an hourly rate yet');
  }

  // Persist booking + payment + initial status-history row atomically.
  const booking = await prisma.$transaction(async (tx) => {
    // Re-check availability inside the tx to narrow the race window.
    await assertSlotAvailable({ companionId, bookingDate, startTime, endTime, client: tx });

    let created = null;
    // Retry on the rare bookingCode collision.
    for (let attempt = 0; attempt < 5 && !created; attempt += 1) {
      try {
        created = await tx.booking.create({
          data: {
            bookingCode: generateBookingCode(),
            customerId,
            companionId,
            categoryId: categoryId ?? null,
            activity,
            durationHours,
            bookingDate,
            startTime,
            endTime,
            meetingLocation,
            meetingPlaceType,
            hourlyRate: D(breakdown.hourlyRate),
            totalAmount: D(breakdown.totalAmount),
            commissionRate: breakdown.commissionRate,
            commissionAmount: D(breakdown.commissionAmount),
            companionPayout: D(breakdown.companionPayout),
            status: 'PENDING',
            notes: notes ?? null,
          },
        });
      } catch (err) {
        if (err?.code === 'P2002') continue; // unique bookingCode collision -> retry
        throw err;
      }
    }
    if (!created) throw ApiError.internal('Could not allocate a booking code');

    await tx.payment.create({
      data: {
        bookingId: created.id,
        customerId,
        amount: D(breakdown.totalAmount),
        currency: 'INR',
        status: 'CREATED',
        method: paymentMethod,
      },
    });

    await tx.bookingStatusHistory.create({
      data: {
        bookingId: created.id,
        status: 'PENDING',
        changedById: customerId,
        note: 'Booking created',
      },
    });

    return created;
  });

  // Create the Razorpay order outside the DB tx (external call). Best-effort: a failure
  // here leaves the booking PENDING with a CREATED payment that can be retried via
  // POST /payments/order. Skipped entirely for cash (pay-in-person) bookings.
  let razorpayOrderId = null;
  if (paymentMethod === 'razorpay') {
    try {
      const order = await createOrder({
        amount: breakdown.totalAmount,
        receipt: booking.bookingCode,
        notes: { bookingId: booking.id, bookingCode: booking.bookingCode, customerId },
      });
      razorpayOrderId = order.id;
      await prisma.payment.update({
        where: { bookingId: booking.id },
        data: { razorpayOrderId: order.id },
      });
    } catch (err) {
      logger.error(`[bookings] Razorpay order failed for ${booking.bookingCode}: ${err.message}`);
    }
  }

  // Notify the companion of the new request.
  await notify(companion.userId, {
    type: 'BOOKING',
    title: 'New booking request',
    body: `You have a new ${activity} booking request (${booking.bookingCode}).`,
    data: { bookingId: booking.id, bookingCode: booking.bookingCode },
  });

  const payment = await prisma.payment.findUnique({ where: { bookingId: booking.id } });
  return {
    booking: await getBookingById(booking.id, customerId, 'CUSTOMER'),
    payment: {
      id: payment.id,
      status: payment.status,
      amount: D(payment.amount).toNumber(),
      currency: payment.currency,
      method: payment.method,
      razorpayOrderId,
      keyId: undefined,
    },
  };
}

// ---- listing + detail ------------------------------------------------------

/** Shared include for booking detail/list responses. */
const bookingInclude = {
  companion: {
    select: {
      id: true,
      hourlyRate: true,
      city: true,
      user: { select: { id: true, fullName: true, profilePhotoUrl: true } },
    },
  },
  customer: { select: { id: true, fullName: true, profilePhotoUrl: true } },
  category: { select: { id: true, slug: true, name: true } },
  payment: {
    select: { id: true, status: true, amount: true, currency: true, razorpayOrderId: true },
  },
};

/** Convert Decimal fields to numbers for JSON. */
function serializeBooking(b) {
  if (!b) return b;
  const out = {
    ...b,
    hourlyRate: b.hourlyRate != null ? D(b.hourlyRate).toNumber() : b.hourlyRate,
    totalAmount: b.totalAmount != null ? D(b.totalAmount).toNumber() : b.totalAmount,
    commissionAmount: b.commissionAmount != null ? D(b.commissionAmount).toNumber() : b.commissionAmount,
    companionPayout: b.companionPayout != null ? D(b.companionPayout).toNumber() : b.companionPayout,
  };
  if (out.companion?.hourlyRate != null) {
    out.companion = { ...out.companion, hourlyRate: D(out.companion.hourlyRate).toNumber() };
  }
  if (out.payment?.amount != null) {
    out.payment = { ...out.payment, amount: D(out.payment.amount).toNumber() };
  }
  return out;
}

/**
 * Role-aware list of a user's bookings.
 *  - CUSTOMER: bookings they placed.
 *  - COMPANION: bookings they received (matched via their companion profile).
 * @param {object} user  req.user (with companion relation when applicable)
 * @param {object} req   for pagination
 * @param {{status?:string}} filters
 */
export async function listBookings(user, req, filters = {}) {
  const { skip, take, page, limit, orderBy } = getPagination(req);

  const where = {};
  if (filters.status) where.status = filters.status;

  if (user.role === 'COMPANION' && user.companion) {
    where.companionId = user.companion.id;
  } else {
    where.customerId = user.id;
  }

  const [rows, total] = await prisma.$transaction([
    prisma.booking.findMany({
      where,
      include: bookingInclude,
      orderBy: orderBy ?? { createdAt: 'desc' },
      skip,
      take,
    }),
    prisma.booking.count({ where }),
  ]);

  return {
    items: rows.map(serializeBooking),
    meta: buildMeta(total, page, limit),
  };
}

/**
 * Fetch a single booking the caller is authorized to see, with status history.
 * @param {string} bookingId
 * @param {string} userId
 * @param {'CUSTOMER'|'COMPANION'|'ADMIN'} role
 * @param {string} [companionId]  the caller's companion profile id (for companions)
 */
export async function getBookingById(bookingId, userId, role, companionId = null) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      ...bookingInclude,
      statusHistory: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!booking) throw ApiError.notFound('Booking not found');

  const isCustomer = booking.customerId === userId;
  const isCompanion = companionId && booking.companionId === companionId;
  if (role !== 'ADMIN' && !isCustomer && !isCompanion) {
    throw ApiError.forbidden('You do not have access to this booking');
  }

  const serialized = serializeBooking(booking);
  // The start code is the customer's secret to reveal in person. The companion
  // must NEVER see it — they have to obtain it from the customer at the meeting.
  if (!(isCustomer || role === 'ADMIN')) {
    delete serialized.startCode;
  }
  return serialized;
}

// ---- status machine --------------------------------------------------------

// Allowed forward transitions for the linear lifecycle.
const FORWARD = {
  PENDING: ['CONFIRMED', 'CANCELLED'],
  CONFIRMED: ['IN_PROGRESS', 'CANCELLED'],
  IN_PROGRESS: ['COMPLETED', 'CANCELLED'],
  COMPLETED: [],
  CANCELLED: [],
  REFUNDED: [],
};

function assertTransition(from, to) {
  const allowed = FORWARD[from] || [];
  if (!allowed.includes(to)) {
    throw ApiError.conflict(`Cannot move booking from ${from} to ${to}`);
  }
}

/** Load a booking (with companion.userId + payment) or throw 404. */
async function loadBookingForAction(bookingId) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      companion: { select: { id: true, userId: true } },
      payment: true,
    },
  });
  if (!booking) throw ApiError.notFound('Booking not found');
  return booking;
}

/** Was this booking actually paid (Razorpay captured / authorized)? */
function isPaid(booking) {
  const s = booking.payment?.status;
  return s === 'CAPTURED' || s === 'AUTHORIZED';
}

/**
 * May the meeting lifecycle proceed without an online capture? True for paid
 * bookings AND cash (pay-in-person) bookings — the companion collects cash at
 * the meeting. Refund logic must keep using isPaid(), never this.
 */
function isPayableInPerson(booking) {
  return isPaid(booking) || booking.payment?.method === 'cash';
}

/** Write a status-history row inside (or outside) a tx. */
function writeHistory(client, { bookingId, status, changedById, note }) {
  return client.bookingStatusHistory.create({
    data: { bookingId, status, changedById, note: note ?? null },
  });
}

/**
 * COMPANION accepts a booking: PENDING/CONFIRMED -> CONFIRMED. Idempotent if already CONFIRMED.
 */
export async function acceptBooking(bookingId, actor) {
  const booking = await loadBookingForAction(bookingId);
  if (!actor.companion || booking.companion.id !== actor.companion.id) {
    throw ApiError.forbidden('Only the assigned companion can accept this booking');
  }
  if (booking.status === 'CONFIRMED') {
    return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
  }
  if (booking.status !== 'PENDING') {
    throw ApiError.conflict(`Cannot accept a ${booking.status} booking`);
  }

  // Mint the meet-at-location start code on acceptance (keep an existing one if the
  // call is retried). The customer reveals it in person so the companion can start.
  const startCode = booking.startCode || generateStartCode();

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: { status: 'CONFIRMED', startCode, startCodeAttempts: 0 },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'CONFIRMED',
      changedById: actor.id,
      note: 'Companion accepted the booking',
    });
  });

  await notify(booking.customerId, {
    type: 'BOOKING',
    title: 'Booking confirmed',
    body: `Your booking ${booking.bookingCode} is confirmed. Show your start code to the companion when you meet to begin.`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });

  return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
}

/**
 * COMPANION rejects a booking -> CANCELLED (+ REFUNDED if it was paid).
 */
export async function rejectBooking(bookingId, actor, reason) {
  const booking = await loadBookingForAction(bookingId);
  if (!actor.companion || booking.companion.id !== actor.companion.id) {
    throw ApiError.forbidden('Only the assigned companion can reject this booking');
  }
  assertTransition(booking.status, 'CANCELLED');

  const paid = isPaid(booking);
  const finalStatus = paid ? 'REFUNDED' : 'CANCELLED';

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: finalStatus,
        cancelledById: actor.id,
        cancellationReason: reason || 'Rejected by companion',
      },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'CANCELLED',
      changedById: actor.id,
      note: reason || 'Companion rejected the booking',
    });
    if (paid) {
      await writeHistory(tx, {
        bookingId,
        status: 'REFUNDED',
        changedById: actor.id,
        note: 'Refund initiated after rejection',
      });
    }
  });

  if (paid) await processRefund(booking);

  await notify(booking.customerId, {
    type: 'BOOKING',
    title: 'Booking declined',
    body: paid
      ? `Booking ${booking.bookingCode} was declined; a refund has been initiated.`
      : `Booking ${booking.bookingCode} was declined by the companion.`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });

  return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
}

/**
 * COMPANION starts a confirmed booking once both parties meet: CONFIRMED -> IN_PROGRESS.
 * Requires the customer's 6-digit start code (entered by the companion at the meeting),
 * proving they are physically together. Stamps the real-world startedAt.
 * @param {string} bookingId
 * @param {object} actor   req.user (companion)
 * @param {string} code    the start code the customer revealed in person
 */
export async function startBooking(bookingId, actor, code) {
  const booking = await loadBookingForAction(bookingId);
  if (!actor.companion || booking.companion.id !== actor.companion.id) {
    throw ApiError.forbidden('Only the assigned companion can start this booking');
  }
  assertTransition(booking.status, 'IN_PROGRESS');
  if (!isPayableInPerson(booking)) {
    throw ApiError.conflict('Booking must be paid before it can start');
  }
  if (!booking.startCode) {
    throw ApiError.conflict('This booking has no start code yet. Ask the customer to refresh.');
  }
  if (booking.startCodeAttempts >= MAX_START_CODE_ATTEMPTS) {
    throw ApiError.forbidden(
      'Too many incorrect start-code attempts. Please ask the customer to verify the code or contact support.',
    );
  }

  const supplied = String(code ?? '').trim();
  if (supplied !== booking.startCode) {
    await prisma.booking.update({
      where: { id: bookingId },
      data: { startCodeAttempts: { increment: 1 } },
    });
    const left = Math.max(0, MAX_START_CODE_ATTEMPTS - (booking.startCodeAttempts + 1));
    throw ApiError.badRequest(
      left > 0
        ? `Incorrect start code. ${left} attempt${left === 1 ? '' : 's'} left.`
        : 'Incorrect start code. No attempts left — please contact support.',
    );
  }

  const startedAt = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: { status: 'IN_PROGRESS', startedAt, startVerifiedById: actor.id },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'IN_PROGRESS',
      changedById: actor.id,
      note: 'Booking started — start code verified at the meeting point',
    });
  });

  await notify(booking.customerId, {
    type: 'BOOKING',
    title: 'Your meetup has started',
    body: `Booking ${booking.bookingCode} is now in progress. Stay in public places and stay safe.`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });

  return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
}

/**
 * ADMIN override: force a confirmed booking to IN_PROGRESS from the panel without the
 * start code (e.g. the customer can't locate it). Stamps startedAt + records the admin.
 * @param {string} bookingId
 * @param {string} adminId
 */
export async function startBookingByAdmin(bookingId, adminId) {
  const booking = await loadBookingForAction(bookingId);
  assertTransition(booking.status, 'IN_PROGRESS');
  if (!isPayableInPerson(booking)) {
    throw ApiError.conflict('Booking must be paid before it can start');
  }

  const startedAt = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: { status: 'IN_PROGRESS', startedAt, startVerifiedById: adminId },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'IN_PROGRESS',
      changedById: adminId,
      note: 'Booking started by admin (panel override)',
    });
  });

  await Promise.all([
    notify(booking.customerId, {
      type: 'BOOKING',
      title: 'Your meetup has started',
      body: `Booking ${booking.bookingCode} was started by support. Stay in public places and stay safe.`,
      data: { bookingId, bookingCode: booking.bookingCode },
    }).catch(() => {}),
    notify(booking.companion.userId, {
      type: 'BOOKING',
      title: 'Booking started',
      body: `Booking ${booking.bookingCode} was started by support.`,
      data: { bookingId, bookingCode: booking.bookingCode },
    }).catch(() => {}),
  ]);

  return getBookingById(bookingId, adminId, 'ADMIN', null);
}

/**
 * COMPANION completes a booking: IN_PROGRESS -> COMPLETED.
 * Credits companion payout, records platform commission, evaluates referral reward,
 * and notifies both parties.
 */
export async function completeBooking(bookingId, actor) {
  const booking = await loadBookingForAction(bookingId);
  if (!actor.companion || booking.companion.id !== actor.companion.id) {
    throw ApiError.forbidden('Only the assigned companion can complete this booking');
  }
  assertTransition(booking.status, 'COMPLETED');

  // Mark completed + write history atomically.
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: { status: 'COMPLETED', completedAt: new Date() },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'COMPLETED',
      changedById: actor.id,
      note: 'Booking completed',
    });
  });

  // Money movement via the shared ledger service. Cash (pay-in-person) bookings
  // don't credit the companion's wallet — they already hold the cash — so we only
  // mark the payment captured + record commission; online bookings credit payout.
  const payment = await prisma.payment.findUnique({
    where: { bookingId },
    select: { method: true },
  });
  const isCash = payment?.method === 'cash';
  try {
    if (isCash) {
      await settleCashBooking(booking);
    } else {
      await creditCompanionEarning(booking); // also bumps totalEarnings + totalBookings
    }
    await recordCommission(booking);
    await applyReferralRewardIfEligible(booking.customerId, booking);
  } catch (err) {
    logger.error(`[bookings] payout/commission failed for ${booking.bookingCode}: ${err.message}`);
  }

  // Notify both parties.
  await notify(booking.companion.userId, {
    type: 'BOOKING',
    title: 'Booking completed',
    body: isCash
      ? `Booking ${booking.bookingCode} is complete. Please collect the cash payment.`
      : `Booking ${booking.bookingCode} is complete. Your earnings have been credited.`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });
  await notify(booking.customerId, {
    type: 'BOOKING',
    title: 'Booking completed',
    body: `Your booking ${booking.bookingCode} is complete. Please leave a review!`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });

  return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
}

/**
 * CUSTOMER cancels a booking before it completes -> CANCELLED (+ REFUNDED if paid).
 */
export async function cancelBooking(bookingId, actor, reason) {
  const booking = await loadBookingForAction(bookingId);
  if (booking.customerId !== actor.id) {
    throw ApiError.forbidden('Only the customer can cancel this booking');
  }
  if (booking.status === 'IN_PROGRESS') {
    throw ApiError.conflict('A booking in progress cannot be cancelled');
  }
  assertTransition(booking.status, 'CANCELLED');

  const paid = isPaid(booking);
  const finalStatus = paid ? 'REFUNDED' : 'CANCELLED';

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        status: finalStatus,
        cancelledById: actor.id,
        cancellationReason: reason,
      },
    });
    await writeHistory(tx, {
      bookingId,
      status: 'CANCELLED',
      changedById: actor.id,
      note: reason || 'Cancelled by customer',
    });
    if (paid) {
      await writeHistory(tx, {
        bookingId,
        status: 'REFUNDED',
        changedById: actor.id,
        note: 'Refund initiated after cancellation',
      });
    }
  });

  if (paid) await processRefund(booking);

  await notify(booking.companion.userId, {
    type: 'BOOKING',
    title: 'Booking cancelled',
    body: `Booking ${booking.bookingCode} was cancelled by the customer.`,
    data: { bookingId, bookingCode: booking.bookingCode },
  });

  return getBookingById(bookingId, actor.id, actor.role, actor.companion?.id);
}

/**
 * Refund a paid booking: attempt the Razorpay gateway refund, then mirror it in the
 * ledger (customer wallet credit + payment status). Wallet credit is the source of
 * truth even if the gateway call is unavailable (e.g. dev/test keys).
 */
async function processRefund(booking) {
  const paymentId = booking.payment?.razorpayPaymentId;
  if (paymentId) {
    try {
      await refundPayment(paymentId, D(booking.totalAmount).toNumber());
    } catch (err) {
      logger.error(`[bookings] gateway refund failed for ${booking.bookingCode}: ${err.message}`);
    }
  }
  try {
    await refundToCustomer(booking);
  } catch (err) {
    logger.error(`[bookings] ledger refund failed for ${booking.bookingCode}: ${err.message}`);
  }

  await notify(booking.customerId, {
    type: 'PAYMENT',
    title: 'Refund processed',
    body: `A refund of ₹${D(booking.totalAmount).toNumber()} for booking ${booking.bookingCode} has been processed.`,
    data: { bookingId: booking.id, bookingCode: booking.bookingCode },
  });
}

export default {
  computeBreakdown,
  quoteBooking,
  createBooking,
  listBookings,
  getBookingById,
  acceptBooking,
  rejectBooking,
  startBooking,
  startBookingByAdmin,
  completeBooking,
  cancelBooking,
};
