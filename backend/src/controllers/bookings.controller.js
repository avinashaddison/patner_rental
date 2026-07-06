// Thin HTTP handlers for the bookings module. Each delegates to bookings.service.js
// and returns the standard { success, data, meta } envelope.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import { config } from '../config/index.js';
import * as bookings from '../services/bookings.service.js';

/** POST /bookings/quote — price breakdown, no DB write. */
export const quote = asyncHandler(async (req, res) => {
  const data = await bookings.quoteBooking(req.body);
  return ok(res, data);
});

/** POST /bookings — create a PENDING booking + Razorpay order. */
export const create = asyncHandler(async (req, res) => {
  const result = await bookings.createBooking(req.user.id, req.body);
  // Surface the Razorpay key id so the client can open Checkout.
  if (result.payment) result.payment.keyId = config.razorpay.keyId;
  return created(res, result);
});

/** GET /bookings — role-aware list. */
export const list = asyncHandler(async (req, res) => {
  const { items, meta } = await bookings.listBookings(req.user, req, {
    status: req.query.status,
  });
  return ok(res, items, meta);
});

/** GET /bookings/:id — detail with status history. */
export const detail = asyncHandler(async (req, res) => {
  const data = await bookings.getBookingById(
    req.params.id,
    req.user.id,
    req.user.role,
    req.user.companion?.id ?? null,
  );
  return ok(res, data);
});

/** POST /bookings/:id/accept — companion confirms. */
export const accept = asyncHandler(async (req, res) => {
  const data = await bookings.acceptBooking(req.params.id, req.user);
  return ok(res, data);
});

/** POST /bookings/:id/reject — companion declines (refund if paid). */
export const reject = asyncHandler(async (req, res) => {
  const data = await bookings.rejectBooking(req.params.id, req.user, req.body.reason);
  return ok(res, data);
});

/** POST /bookings/:id/start — companion starts the meetup with the customer's code. */
export const start = asyncHandler(async (req, res) => {
  const data = await bookings.startBooking(req.params.id, req.user, req.body.code);
  return ok(res, data);
});

/** POST /bookings/:id/complete — companion completes (triggers payout + referral). */
export const complete = asyncHandler(async (req, res) => {
  const data = await bookings.completeBooking(req.params.id, req.user);
  return ok(res, data);
});

/** POST /bookings/:id/cancel — customer cancels (refund if paid). */
export const cancel = asyncHandler(async (req, res) => {
  const data = await bookings.cancelBooking(req.params.id, req.user, req.body.reason);
  return ok(res, data);
});

export default { quote, create, list, detail, accept, reject, start, complete, cancel };
