// Payments routes — auto-mounted at /api/payments.
// NOTE: /payments/webhook receives a RAW body (express.raw is registered for this
// exact path in app.js BEFORE the JSON parser) so the signature can be verified.
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  createOrderSchema,
  verifyPaymentSchema,
  paymentByBookingParamsSchema,
  createUpiOrderSchema,
  verifyUpiSchema,
  createQrOrderSchema,
  verifyQrSchema,
  checkQrUtrSchema,
} from '../validators/payments.validator.js';
import {
  postOrder,
  postVerify,
  postWebhook,
  getByBooking,
  postUpiOrder,
  postUpiVerify,
  postUpiWebhook,
  getUpiRedirect,
  postQrOrder,
  postQrVerify,
  postQrCheckUtr,
} from '../controllers/payments.controller.js';

const router = Router();

// Razorpay webhook — no user auth; verified by signature over the raw body.
router.post('/webhook', asyncHandler(postWebhook));

// ---- UPIGateway (ekqr.in) --------------------------------------------------

// Webhook — unsigned urlencoded post; the service re-verifies with the gateway.
router.post('/upi/webhook', asyncHandler(postUpiWebhook));

// Browser landing page after the hosted payment flow.
router.get('/upi/redirect', asyncHandler(getUpiRedirect));

router.post(
  '/upi/order',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(createUpiOrderSchema),
  asyncHandler(postUpiOrder),
);

router.post(
  '/upi/verify',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(verifyUpiSchema),
  asyncHandler(postUpiVerify),
);

// ---- Self-hosted UPI QR (bank-email confirmed) ------------------------------

router.post(
  '/qr/order',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(createQrOrderSchema),
  asyncHandler(postQrOrder),
);

router.post(
  '/qr/verify',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(verifyQrSchema),
  asyncHandler(postQrVerify),
);

router.post(
  '/qr/check-utr',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(checkQrUtrSchema),
  asyncHandler(postQrCheckUtr),
);

router.post(
  '/order',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(createOrderSchema),
  asyncHandler(postOrder),
);

router.post(
  '/verify',
  requireAuth,
  requireRole('CUSTOMER', 'COMPANION'),
  validate(verifyPaymentSchema),
  asyncHandler(postVerify),
);

router.get(
  '/:bookingId',
  requireAuth,
  validate(paymentByBookingParamsSchema, 'params'),
  asyncHandler(getByBooking),
);

export default router;
