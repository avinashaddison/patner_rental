// Bookings routes. Auto-mounted at /api/bookings by routes/index.js.
// Customer actions: quote, create, cancel. Companion actions: accept, reject, start,
// complete. List + detail are role-aware (a user only sees their own bookings).
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { apiLimiter } from '../middleware/rateLimit.js';
import {
  quoteSchema,
  createBookingSchema,
  listBookingsQuerySchema,
  bookingIdParamSchema,
  startBookingSchema,
  rejectBookingSchema,
  cancelBookingSchema,
} from '../validators/bookings.validator.js';
import * as ctrl from '../controllers/bookings.controller.js';

const router = Router();

// Every bookings endpoint requires an authenticated user.
router.use(requireAuth);

// --- Booking as a customer: quote + create ---
// Companions can book other companions too (they act as the customer for
// that booking); the service still forbids booking yourself.
router.post(
  '/quote',
  requireRole('CUSTOMER', 'COMPANION'),
  validate(quoteSchema),
  ctrl.quote,
);

router.post(
  '/',
  requireRole('CUSTOMER', 'COMPANION'),
  apiLimiter,
  validate(createBookingSchema),
  ctrl.create,
);

// --- Role-aware list + detail ---
router.get('/', validate(listBookingsQuerySchema, 'query'), ctrl.list);
router.get('/:id', validate(bookingIdParamSchema, 'params'), ctrl.detail);

// --- Companion transitions ---
router.post(
  '/:id/accept',
  requireRole('COMPANION'),
  validate(bookingIdParamSchema, 'params'),
  ctrl.accept,
);

router.post(
  '/:id/reject',
  requireRole('COMPANION'),
  validate(bookingIdParamSchema, 'params'),
  validate(rejectBookingSchema),
  ctrl.reject,
);

router.post(
  '/:id/start',
  requireRole('COMPANION'),
  validate(bookingIdParamSchema, 'params'),
  validate(startBookingSchema),
  ctrl.start,
);

router.post(
  '/:id/complete',
  requireRole('COMPANION'),
  validate(bookingIdParamSchema, 'params'),
  ctrl.complete,
);

// --- Customer cancel ---
router.post(
  '/:id/cancel',
  requireRole('CUSTOMER'),
  validate(bookingIdParamSchema, 'params'),
  validate(cancelBookingSchema),
  ctrl.cancel,
);

export default router;
