// Admin API router — auto-mounted at /api/admin by routes/index.js.
// Every route except POST /auth/login is protected by requireAdmin (admin JWT).
// Matches docs/API.md "ADMIN API" exactly (paths, methods, bodies).
import { Router } from 'express';
import multer from 'multer';
import { requireAdmin } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import * as ctrl from '../controllers/admin.controller.js';
import {
  loginSchema,
  revenueQuerySchema,
  userListQuerySchema,
  blockUserSchema,
  companionListQuerySchema,
  rejectReasonSchema,
  featureSchema,
  addCompanionKycSchema,
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
} from '../validators/admin.validator.js';

const router = Router();

// In-memory upload for category icons; streamed straight to Cloudinary (5 MB cap).
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

// ---- Auth (login is public; me requires admin) ----------------------------

router.post('/auth/login', validate(loginSchema), asyncHandler(ctrl.login));

// Everything below requires a valid admin token.
router.use(requireAdmin);

router.get('/auth/me', asyncHandler(ctrl.me));

// ---- Dashboard + analytics ------------------------------------------------

router.get('/dashboard', asyncHandler(ctrl.dashboard));
router.get('/analytics/revenue', validate(revenueQuerySchema, 'query'), asyncHandler(ctrl.revenueAnalytics));
router.get('/analytics/overview', asyncHandler(ctrl.analyticsOverview));

// ---- Users ----------------------------------------------------------------

router.get('/users', validate(userListQuerySchema, 'query'), asyncHandler(ctrl.listUsers));
router.get('/users/:id', asyncHandler(ctrl.getUser));
router.post('/users/:id/block', validate(blockUserSchema), asyncHandler(ctrl.blockUser));
router.post('/users/:id/unblock', asyncHandler(ctrl.unblockUser));

// ---- Companions -----------------------------------------------------------

router.get('/companions', validate(companionListQuerySchema, 'query'), asyncHandler(ctrl.listCompanions));
router.get('/companions/:id', asyncHandler(ctrl.getCompanion));
router.post('/companions/:id/approve', asyncHandler(ctrl.approveCompanion));
router.post('/companions/:id/reject', validate(rejectReasonSchema), asyncHandler(ctrl.rejectCompanion));
router.post('/companions/:id/suspend', validate(rejectReasonSchema), asyncHandler(ctrl.suspendCompanion));
router.post('/companions/:id/feature', validate(featureSchema), asyncHandler(ctrl.featureCompanion));
// Admin manually uploads a KYC document (multipart image + docType), recorded as
// approved. multer parses the form BEFORE validate reads req.body.
router.post(
  '/companions/:id/kyc',
  upload.single('image'),
  validate(addCompanionKycSchema),
  asyncHandler(ctrl.addCompanionKyc),
);

// ---- KYC ------------------------------------------------------------------

router.get('/kyc', validate(kycQuerySchema, 'query'), asyncHandler(ctrl.listKyc));
router.post('/kyc/:id/approve', asyncHandler(ctrl.approveKyc));
router.post('/kyc/:id/reject', validate(rejectReasonSchema), asyncHandler(ctrl.rejectKyc));

// ---- Bookings -------------------------------------------------------------

router.get('/bookings', validate(bookingListQuerySchema, 'query'), asyncHandler(ctrl.listBookings));
router.get('/bookings/:id', asyncHandler(ctrl.getBooking));
router.post('/bookings/:id/start', asyncHandler(ctrl.startBooking));
router.post('/bookings/:id/cancel', validate(cancelBookingSchema), asyncHandler(ctrl.cancelBooking));
router.post('/bookings/:id/refund', validate(refundBookingSchema), asyncHandler(ctrl.refundBooking));

// ---- Posts (moderation) ---------------------------------------------------

router.get('/posts', validate(postListQuerySchema, 'query'), asyncHandler(ctrl.listPosts));
router.get('/posts/:id', asyncHandler(ctrl.getPost));
router.delete('/posts/:id', asyncHandler(ctrl.removePost));

// ---- Payments -------------------------------------------------------------

router.get('/payments', validate(paymentListQuerySchema, 'query'), asyncHandler(ctrl.listPayments));

// ---- Payouts --------------------------------------------------------------

router.get('/payouts', validate(payoutListQuerySchema, 'query'), asyncHandler(ctrl.listPayouts));
router.post('/payouts/:id/process', validate(processPayoutSchema), asyncHandler(ctrl.processPayout));
router.post('/payouts/:id/reject', validate(rejectReasonSchema), asyncHandler(ctrl.rejectPayout));

// ---- Reports --------------------------------------------------------------

router.get('/reports', validate(reportListQuerySchema, 'query'), asyncHandler(ctrl.listReports));
router.post('/reports/:id/resolve', validate(resolveReportSchema), asyncHandler(ctrl.resolveReport));

// ---- Support tickets ------------------------------------------------------

router.get('/support/unread-count', asyncHandler(ctrl.supportUnreadCount));
router.get('/support/tickets', validate(ticketListQuerySchema, 'query'), asyncHandler(ctrl.listTickets));
router.get('/support/tickets/:id', asyncHandler(ctrl.getTicket));
router.post('/support/tickets/:id/reply', validate(replyTicketSchema), asyncHandler(ctrl.replyToTicket));
router.post('/support/tickets/:id/status', validate(ticketStatusSchema), asyncHandler(ctrl.updateTicketStatus));

// ---- SOS ------------------------------------------------------------------

router.get('/sos', validate(sosListQuerySchema, 'query'), asyncHandler(ctrl.listSos));
router.post('/sos/:id/resolve', validate(resolveSosSchema), asyncHandler(ctrl.resolveSos));

// ---- Settings -------------------------------------------------------------

router.get('/settings', asyncHandler(ctrl.listSettings));
// Login hero image upload — declared before the generic ':key' PUT (different
// method/path, but keep it grouped). Multipart field name: "image".
router.post('/settings/login-hero', upload.single('image'), asyncHandler(ctrl.uploadLoginHero));
router.delete('/settings/login-hero', asyncHandler(ctrl.clearLoginHero));
// Onboarding step photos (slot 1-3). Multipart field name: "image".
router.post('/settings/onboarding-hero/:slot', upload.single('image'), asyncHandler(ctrl.uploadOnboardingHero));
router.delete('/settings/onboarding-hero/:slot', asyncHandler(ctrl.clearOnboardingHero));
// Home carousel banner photos (slot 1-3). Multipart field name: "image".
router.post('/settings/home-banner/:slot', upload.single('image'), asyncHandler(ctrl.uploadHomeBanner));
router.delete('/settings/home-banner/:slot', asyncHandler(ctrl.clearHomeBanner));
router.put('/settings/:key', validate(updateSettingSchema), asyncHandler(ctrl.updateSetting));

// ---- Categories -----------------------------------------------------------

router.get('/categories', asyncHandler(ctrl.listCategories));
router.post('/categories/:id/icon', upload.single('image'), asyncHandler(ctrl.uploadCategoryIcon));
router.delete('/categories/:id/icon', asyncHandler(ctrl.deleteCategoryIcon));

export default router;
