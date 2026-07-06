// Zod request schemas for the Admin API. These validate + coerce admin request
// bodies/queries before they reach the controller (see middleware/validate.js).
import { z } from 'zod';

// ---- Shared primitives ----------------------------------------------------

const trimmed = (max = 500) => z.string().trim().min(1).max(max);
const optionalReason = z.string().trim().min(1).max(1000);

const COMPANION_STATUSES = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'];
const BOOKING_STATUSES = ['PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'REFUNDED'];
const PAYOUT_STATUSES = ['REQUESTED', 'PROCESSING', 'COMPLETED', 'FAILED', 'REJECTED'];
const PAYMENT_STATUSES = ['CREATED', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED'];
const KYC_STATUSES = ['PENDING', 'SUBMITTED', 'APPROVED', 'REJECTED'];
const REPORT_STATUSES = ['OPEN', 'REVIEWING', 'RESOLVED', 'DISMISSED'];
const TICKET_STATUSES = ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'];
const SOS_STATUSES = ['ACTIVE', 'RESOLVED', 'CANCELLED'];
const USER_ROLES = ['CUSTOMER', 'COMPANION', 'ADMIN'];
const REVENUE_PERIODS = ['daily', 'weekly', 'monthly', 'yearly'];

// ---- Auth -----------------------------------------------------------------

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1).max(200),
});

// ---- Analytics ------------------------------------------------------------

export const revenueQuerySchema = z.object({
  period: z.enum(REVENUE_PERIODS).default('daily'),
});

// ---- Users ----------------------------------------------------------------

export const userListQuerySchema = z.object({
  role: z.enum(USER_ROLES).optional(),
  blocked: z
    .enum(['true', 'false'])
    .transform((v) => v === 'true')
    .optional(),
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const blockUserSchema = z.object({
  reason: optionalReason,
});

// ---- Companions -----------------------------------------------------------

export const companionListQuerySchema = z.object({
  status: z.enum(COMPANION_STATUSES).optional(),
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const rejectReasonSchema = z.object({
  reason: optionalReason,
});

export const featureSchema = z.object({
  isFeatured: z.boolean(),
});

// POST /admin/companions/:id/kyc — admin manually adds a KYC document (multipart:
// an `image` file plus these body fields). docType picks which document it is.
export const addCompanionKycSchema = z.object({
  docType: z.enum(['GOVERNMENT_ID', 'SELFIE']),
  documentNumber: z.string().trim().max(60).optional(),
});

// ---- KYC ------------------------------------------------------------------

export const kycQuerySchema = z.object({
  status: z.enum(KYC_STATUSES).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

// ---- Bookings -------------------------------------------------------------

export const bookingListQuerySchema = z.object({
  status: z.enum(BOOKING_STATUSES).optional(),
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const cancelBookingSchema = z.object({
  reason: optionalReason,
});

export const refundBookingSchema = z.object({
  amount: z.coerce.number().positive().max(1_000_000).optional(),
});

// ---- Payments -------------------------------------------------------------

export const paymentListQuerySchema = z.object({
  status: z.enum(PAYMENT_STATUSES).optional(),
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

// ---- Payouts --------------------------------------------------------------

export const payoutListQuerySchema = z.object({
  status: z.enum(PAYOUT_STATUSES).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const processPayoutSchema = z.object({
  notes: z.string().trim().max(1000).optional(),
});

// ---- Reports --------------------------------------------------------------

export const reportListQuerySchema = z.object({
  status: z.enum(REPORT_STATUSES).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const resolveReportSchema = z.object({
  resolutionNotes: trimmed(1000),
  status: z.enum(['RESOLVED', 'DISMISSED']).default('RESOLVED'),
});

// ---- Posts (moderation) ---------------------------------------------------

export const postListQuerySchema = z.object({
  status: z.enum(['PUBLISHED', 'REMOVED']).optional(),
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

// ---- Support tickets ------------------------------------------------------

export const ticketListQuerySchema = z.object({
  status: z.enum(TICKET_STATUSES).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const replyTicketSchema = z.object({
  message: trimmed(2000),
});

export const ticketStatusSchema = z.object({
  status: z.enum(TICKET_STATUSES),
});

// ---- SOS ------------------------------------------------------------------

export const sosListQuerySchema = z.object({
  status: z.enum(SOS_STATUSES).optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

export const resolveSosSchema = z.object({
  note: z.string().trim().max(1000).optional(),
});

// ---- Settings -------------------------------------------------------------

// PUT /admin/settings/:key body — value may be any JSON-serializable shape.
export const updateSettingSchema = z.object({
  value: z.any().refine((v) => v !== undefined, { message: 'value is required' }),
  description: z.string().trim().max(500).optional(),
});

export default {
  loginSchema,
  revenueQuerySchema,
  userListQuerySchema,
  blockUserSchema,
  companionListQuerySchema,
  rejectReasonSchema,
  featureSchema,
  kycQuerySchema,
  bookingListQuerySchema,
  cancelBookingSchema,
  refundBookingSchema,
  paymentListQuerySchema,
  payoutListQuerySchema,
  processPayoutSchema,
  reportListQuerySchema,
  resolveReportSchema,
  postListQuerySchema,
  ticketListQuerySchema,
  replyTicketSchema,
  ticketStatusSchema,
  sosListQuerySchema,
  resolveSosSchema,
  updateSettingSchema,
};
