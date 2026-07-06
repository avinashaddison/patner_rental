// Zod request schemas for the bookings module.
// Enforces the safety policy: companionship-only activities, public-place meetings,
// fixed durations, 18+ (age enforced at registration). Field names match docs/API.md.
import { z } from 'zod';
import {
  BOOKING_DURATIONS,
  ALLOWED_PLACE_TYPES,
  ALLOWED_ACTIVITIES,
} from '../config/constants.js';

const uuid = z.string().uuid('Invalid id');

// Durations are a fixed enum (1|2|4|6 hours). Coerce so "2" from JSON still validates.
const durationHours = z.coerce
  .number()
  .int()
  .refine((v) => BOOKING_DURATIONS.includes(v), {
    message: `durationHours must be one of ${BOOKING_DURATIONS.join(', ')}`,
  });

// "HH:mm" 24-hour time.
const timeHHmm = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'startTime must be HH:mm (24-hour)');

// YYYY-MM-DD calendar date (coerced + validated into a real Date downstream).
const dateYMD = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'bookingDate must be YYYY-MM-DD');

// Public-place-only meeting types. Private residences / hotel rooms are rejected.
const meetingPlaceType = z.enum(ALLOWED_PLACE_TYPES, {
  errorMap: () => ({
    message: `meetingPlaceType must be a public place: ${ALLOWED_PLACE_TYPES.join(', ')}`,
  }),
});

// Companionship-only activity list.
const activity = z.enum(ALLOWED_ACTIVITIES, {
  errorMap: () => ({
    message: `activity must be a companionship activity: ${ALLOWED_ACTIVITIES.join(', ')}`,
  }),
});

/** POST /bookings/quote */
export const quoteSchema = z.object({
  companionId: uuid,
  durationHours,
});

/** POST /bookings */
export const createBookingSchema = z.object({
  companionId: uuid,
  categoryId: uuid.optional(),
  activity,
  durationHours,
  bookingDate: dateYMD,
  startTime: timeHHmm,
  meetingLocation: z.string().trim().min(3, 'meetingLocation is required').max(200),
  meetingPlaceType,
  notes: z.string().trim().max(1000).optional(),
  // How the customer will pay: 'razorpay' (online, default) or 'cash' (pay in
  // person). Availability is enforced server-side against the admin toggles.
  paymentMethod: z.enum(['razorpay', 'cash']).optional().default('razorpay'),
});

/** GET /bookings?status= and GET /companion/bookings?status= */
export const listBookingsQuerySchema = z.object({
  status: z
    .enum(['PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'REFUNDED'])
    .optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

/** Route params carrying a booking id. */
export const bookingIdParamSchema = z.object({
  id: uuid,
});

/** POST /bookings/:id/start — companion enters the customer's 6-digit start code. */
export const startBookingSchema = z.object({
  code: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'Enter the 6-digit start code from the customer'),
});

/** POST /bookings/:id/reject — companion reason. */
export const rejectBookingSchema = z.object({
  reason: z.string().trim().max(500).optional(),
});

/** POST /bookings/:id/cancel — customer reason (required). */
export const cancelBookingSchema = z.object({
  reason: z.string().trim().min(3, 'A cancellation reason is required').max(500),
});

export default {
  quoteSchema,
  createBookingSchema,
  listBookingsQuerySchema,
  bookingIdParamSchema,
  startBookingSchema,
  rejectBookingSchema,
  cancelBookingSchema,
};
