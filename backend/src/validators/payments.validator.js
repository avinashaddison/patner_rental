// Zod request schemas for the payments domain.
import { z } from 'zod';

/** POST /payments/order — create/return a Razorpay order for a booking. */
export const createOrderSchema = z.object({
  bookingId: z.string().uuid('bookingId must be a valid id'),
});

/** POST /payments/verify — verify a completed Razorpay checkout. */
export const verifyPaymentSchema = z.object({
  razorpayOrderId: z.string().min(1, 'razorpayOrderId is required'),
  razorpayPaymentId: z.string().min(1, 'razorpayPaymentId is required'),
  razorpaySignature: z.string().min(1, 'razorpaySignature is required'),
});

/** GET /payments/:bookingId */
export const paymentByBookingParamsSchema = z.object({
  bookingId: z.string().uuid('bookingId must be a valid id'),
});

/** POST /payments/upi/order — create a UPIGateway order for a booking. */
export const createUpiOrderSchema = z.object({
  bookingId: z.string().uuid('bookingId must be a valid id'),
});

/** POST /payments/upi/verify — poll + capture a UPIGateway payment. */
export const verifyUpiSchema = z.object({
  clientTxnId: z.string().trim().min(1, 'clientTxnId is required').max(64),
});

/** POST /payments/qr/order — create a self-hosted UPI QR order for a booking. */
export const createQrOrderSchema = z.object({
  bookingId: z.string().uuid('bookingId must be a valid id'),
});

/** POST /payments/qr/verify — poll a QR payment by its reference. */
export const verifyQrSchema = z.object({
  ref: z.string().trim().min(1, 'ref is required').max(64),
});

/** POST /payments/qr/check-utr — manual UTR fallback for a QR payment. */
export const checkQrUtrSchema = z.object({
  ref: z.string().trim().min(1, 'ref is required').max(64),
  utr: z
    .string()
    .trim()
    .transform((v) => v.replace(/\s+/g, ''))
    .refine((v) => /^\d{9,18}$/.test(v), 'Enter a valid UTR / reference number (9–18 digits)'),
});

export default {
  createOrderSchema,
  verifyPaymentSchema,
  paymentByBookingParamsSchema,
  createUpiOrderSchema,
  verifyUpiSchema,
  createQrOrderSchema,
  verifyQrSchema,
  checkQrUtrSchema,
};
