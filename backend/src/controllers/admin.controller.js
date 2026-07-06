// Thin HTTP handlers for the Admin API. Parse request -> call admin.service ->
// send the standard envelope. Pagination meta via utils/pagination. Admin identity
// comes from req.admin (set by requireAdmin).
import { ok, created, ApiError } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import * as adminService from '../services/admin.service.js';
import * as categoriesService from '../services/categories.service.js';
import { uploadImageBuffer } from '../lib/cloudinary.js';
import { setSetting } from '../services/settings.service.js';

// ---- Auth -----------------------------------------------------------------

export const login = async (req, res) => {
  const { token, admin } = await adminService.login(req.body);
  return ok(res, { token, admin });
};

export const me = async (req, res) => {
  const admin = await adminService.getAdminById(req.admin.id);
  return ok(res, admin);
};

// ---- Dashboard + analytics ------------------------------------------------

export const dashboard = async (_req, res) => {
  const data = await adminService.getDashboard();
  return ok(res, data);
};

export const revenueAnalytics = async (req, res) => {
  const data = await adminService.getRevenueSeries(req.query.period);
  return ok(res, data);
};

export const analyticsOverview = async (_req, res) => {
  const data = await adminService.getAnalyticsOverview();
  return ok(res, data);
};

// ---- Users ----------------------------------------------------------------

export const listUsers = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listUsers(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const getUser = async (req, res) => {
  const data = await adminService.getUserDetail(req.params.id);
  return ok(res, data);
};

export const blockUser = async (req, res) => {
  const data = await adminService.blockUser(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

export const unblockUser = async (req, res) => {
  const data = await adminService.unblockUser(req.params.id, req.admin.id);
  return ok(res, data);
};

// ---- Companions -----------------------------------------------------------

export const listCompanions = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listCompanions(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const getCompanion = async (req, res) => {
  const data = await adminService.getCompanionDetail(req.params.id);
  return ok(res, data);
};

export const approveCompanion = async (req, res) => {
  const data = await adminService.approveCompanion(req.params.id, req.admin.id);
  return ok(res, data);
};

export const rejectCompanion = async (req, res) => {
  const data = await adminService.rejectCompanion(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

export const suspendCompanion = async (req, res) => {
  const data = await adminService.suspendCompanion(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

export const featureCompanion = async (req, res) => {
  const data = await adminService.featureCompanion(req.params.id, req.body.isFeatured, req.admin.id);
  return ok(res, data);
};

/** POST /admin/companions/:id/kyc — admin manually uploads + approves a KYC document. */
export const addCompanionKyc = async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No image file uploaded (field "image")');
  const data = await adminService.addCompanionKyc(
    req.params.id,
    {
      docType: req.body.docType,
      documentNumber: req.body.documentNumber,
      buffer: req.file.buffer,
    },
    req.admin.id,
  );
  return created(res, data);
};

// ---- KYC ------------------------------------------------------------------

export const listKyc = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listKyc(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const approveKyc = async (req, res) => {
  const data = await adminService.approveKyc(req.params.id, req.admin.id);
  return ok(res, data);
};

export const rejectKyc = async (req, res) => {
  const data = await adminService.rejectKyc(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

// ---- Bookings -------------------------------------------------------------

export const listBookings = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listBookings(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const getBooking = async (req, res) => {
  const data = await adminService.getBookingDetail(req.params.id);
  return ok(res, data);
};

export const startBooking = async (req, res) => {
  const data = await adminService.startBooking(req.params.id, req.admin.id);
  return ok(res, data);
};

export const cancelBooking = async (req, res) => {
  const data = await adminService.cancelBooking(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

export const refundBooking = async (req, res) => {
  const data = await adminService.refundBooking(req.params.id, req.body.amount, req.admin.id);
  return ok(res, data);
};

// ---- Posts (moderation) ---------------------------------------------------

export const listPosts = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listPosts(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const getPost = async (req, res) => {
  const data = await adminService.getPostDetail(req.params.id);
  return ok(res, data);
};

export const removePost = async (req, res) => {
  const data = await adminService.removePost(req.params.id, req.admin.id);
  return ok(res, data);
};

// ---- Payments -------------------------------------------------------------

export const listPayments = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total, summary } = await adminService.listPayments(req.query, { skip, take, orderBy });
  return ok(res, items, { ...buildMeta(total, page, limit), summary });
};

// ---- Payouts --------------------------------------------------------------

export const listPayouts = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listPayouts(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const processPayout = async (req, res) => {
  const data = await adminService.processPayout(req.params.id, req.body.notes, req.admin.id);
  return ok(res, data);
};

export const rejectPayout = async (req, res) => {
  const data = await adminService.rejectPayout(req.params.id, req.body.reason, req.admin.id);
  return ok(res, data);
};

// ---- Reports --------------------------------------------------------------

export const listReports = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listReports(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const resolveReport = async (req, res) => {
  const data = await adminService.resolveReport(req.params.id, req.body, req.admin.id);
  return ok(res, data);
};

// ---- Support tickets ------------------------------------------------------

export const listTickets = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listTickets(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const getTicket = async (req, res) => {
  const data = await adminService.getTicketDetail(req.params.id);
  return ok(res, data);
};

export const replyToTicket = async (req, res) => {
  const data = await adminService.replyToTicket(req.params.id, req.body.message, req.admin.id);
  return created(res, data);
};

export const updateTicketStatus = async (req, res) => {
  const data = await adminService.updateTicketStatus(req.params.id, req.body.status, req.admin.id);
  return ok(res, data);
};

export const supportUnreadCount = async (_req, res) => {
  const count = await adminService.countAwaitingReply();
  return ok(res, { count });
};

// ---- SOS ------------------------------------------------------------------

export const listSos = async (req, res) => {
  const { skip, take, page, limit, orderBy } = getPagination(req);
  const { items, total } = await adminService.listSos(req.query, { skip, take, orderBy });
  return ok(res, items, buildMeta(total, page, limit));
};

export const resolveSos = async (req, res) => {
  const data = await adminService.resolveSos(req.params.id, req.body.note, req.admin.id);
  return ok(res, data);
};

// ---- Settings -------------------------------------------------------------

export const listSettings = async (_req, res) => {
  const data = await adminService.listSettings();
  return ok(res, data);
};

export const updateSetting = async (req, res) => {
  const data = await adminService.updateSetting(
    req.params.key,
    req.body.value,
    req.body.description,
    req.admin.id,
  );
  return ok(res, data);
};

// ---- Categories -----------------------------------------------------------

export const listCategories = async (_req, res) => {
  const data = await categoriesService.listCategories();
  return ok(res, data);
};

export const uploadCategoryIcon = async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No image file uploaded (field "image")');
  const category = await categoriesService.getCategoryOrThrow(req.params.id);
  const iconUrl = await uploadImageBuffer({
    buffer: req.file.buffer,
    folder: 'companion-ranchi/categories',
    publicId: category.slug,
  });
  const data = await categoriesService.setCategoryIcon(category.id, iconUrl);
  return ok(res, data);
};

export const deleteCategoryIcon = async (req, res) => {
  const data = await categoriesService.clearCategoryIcon(req.params.id);
  return ok(res, data);
};

// ---- Login hero image (mobile login screen) -------------------------------

/**
 * POST /admin/settings/login-hero — upload the couple photo shown on the app's
 * login screen. Streams the in-memory file to Cloudinary, then stores the public
 * URL in the `login_hero_image_url` setting (surfaced via GET /meta/config).
 */
export const uploadLoginHero = async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No image file uploaded (field "image")');
  const url = await uploadImageBuffer({
    buffer: req.file.buffer,
    folder: 'companion-ranchi/settings',
    publicId: 'login-hero',
  });
  await setSetting('login_hero_image_url', url, {
    updatedById: req.admin.id,
    description: 'Mobile login screen hero image',
  });
  return ok(res, { url });
};

/** DELETE /admin/settings/login-hero — clear it; the app falls back to its bundled photo. */
export const clearLoginHero = async (req, res) => {
  await setSetting('login_hero_image_url', '', { updatedById: req.admin.id });
  return ok(res, { url: '' });
};

// ---- Onboarding step images (mobile intro carousel) -----------------------

const ONBOARDING_SLOTS = [1, 2, 3];

/** Validate a 1–3 slot param and return its settings key. */
function onboardingKey(slotRaw) {
  const slot = Number.parseInt(slotRaw, 10);
  if (!ONBOARDING_SLOTS.includes(slot)) {
    throw ApiError.badRequest('Onboarding slot must be 1, 2 or 3');
  }
  return { slot, key: `onboarding_image_${slot}` };
}

/**
 * POST /admin/settings/onboarding-hero/:slot — upload the photo for onboarding
 * step :slot (1-3). Stores the Cloudinary URL in `onboarding_image_{slot}`
 * (surfaced via GET /meta/config → onboardingImageUrls).
 */
export const uploadOnboardingHero = async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No image file uploaded (field "image")');
  const { slot, key } = onboardingKey(req.params.slot);
  const url = await uploadImageBuffer({
    buffer: req.file.buffer,
    folder: 'companion-ranchi/settings',
    publicId: `onboarding-${slot}`,
  });
  await setSetting(key, url, {
    updatedById: req.admin.id,
    description: `Onboarding step ${slot} image`,
  });
  return ok(res, { url, slot });
};

/** DELETE /admin/settings/onboarding-hero/:slot — clear it; the app falls back to bundled. */
export const clearOnboardingHero = async (req, res) => {
  const { slot, key } = onboardingKey(req.params.slot);
  await setSetting(key, '', { updatedById: req.admin.id });
  return ok(res, { url: '', slot });
};

// ---- Home banner images (customer home carousel) --------------------------

const HOME_BANNER_SLOTS = [1, 2, 3];

/** Validate a 1–3 slot param and return its settings key. */
function homeBannerKey(slotRaw) {
  const slot = Number.parseInt(slotRaw, 10);
  if (!HOME_BANNER_SLOTS.includes(slot)) {
    throw ApiError.badRequest('Home banner slot must be 1, 2 or 3');
  }
  return { slot, key: `home_banner_${slot}` };
}

/**
 * POST /admin/settings/home-banner/:slot — upload the promo image for the home
 * carousel slide :slot (1-3). Stores the Cloudinary URL in `home_banner_{slot}`
 * (surfaced via GET /meta/config → homeBannerImageUrls).
 */
export const uploadHomeBanner = async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No image file uploaded (field "image")');
  const { slot, key } = homeBannerKey(req.params.slot);
  const url = await uploadImageBuffer({
    buffer: req.file.buffer,
    folder: 'companion-ranchi/settings',
    publicId: `home-banner-${slot}`,
  });
  await setSetting(key, url, {
    updatedById: req.admin.id,
    description: `Home banner slide ${slot} image`,
  });
  return ok(res, { url, slot });
};

/** DELETE /admin/settings/home-banner/:slot — clear it; the app falls back to its default card. */
export const clearHomeBanner = async (req, res) => {
  const { slot, key } = homeBannerKey(req.params.slot);
  await setSetting(key, '', { updatedById: req.admin.id });
  return ok(res, { url: '', slot });
};

export default {
  login,
  me,
  dashboard,
  revenueAnalytics,
  analyticsOverview,
  listUsers,
  getUser,
  blockUser,
  unblockUser,
  listCompanions,
  getCompanion,
  approveCompanion,
  rejectCompanion,
  suspendCompanion,
  featureCompanion,
  listKyc,
  approveKyc,
  rejectKyc,
  listBookings,
  getBooking,
  startBooking,
  cancelBooking,
  refundBooking,
  listPosts,
  getPost,
  removePost,
  listPayments,
  listPayouts,
  processPayout,
  rejectPayout,
  listReports,
  resolveReport,
  listTickets,
  getTicket,
  replyToTicket,
  updateTicketStatus,
  supportUnreadCount,
  listSos,
  resolveSos,
  listSettings,
  updateSetting,
  listCategories,
  uploadCategoryIcon,
  deleteCategoryIcon,
  uploadLoginHero,
  clearLoginHero,
  uploadOnboardingHero,
  clearOnboardingHero,
  uploadHomeBanner,
  clearHomeBanner,
};
