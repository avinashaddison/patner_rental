// Public meta/config endpoints. No auth required.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok } from '../utils/apiResponse.js';
import { prisma } from '../lib/prisma.js';
import { config } from '../config/index.js';
import {
  CATEGORIES,
  BOOKING_DURATIONS,
  ALLOWED_PLACE_TYPES,
  ALLOWED_ACTIVITIES,
} from '../config/constants.js';
import {
  getSetting,
  getCommissionRate,
  getCategoryIconScale,
  getEnabledPaymentMethods,
} from '../services/settings.service.js';

/**
 * GET /meta/config
 * Public app bootstrap config: categories, durations, cities, commissionRate, minAge,
 * placeTypes, activities. Reads live values from settings/DB with constant fallbacks.
 */
export const getConfig = asyncHandler(async (_req, res) => {
  // Categories: prefer the seeded DB rows (active, ordered); fall back to constants.
  let categories;
  try {
    const rows = await prisma.category.findMany({
      where: { isActive: true },
      orderBy: { sortOrder: 'asc' },
      select: { slug: true, name: true, iconUrl: true, sortOrder: true },
    });
    categories = rows.length
      ? rows
      : CATEGORIES.map((c) => ({ slug: c.slug, name: c.name, iconUrl: null, sortOrder: c.sortOrder }));
  } catch {
    categories = CATEGORIES.map((c) => ({
      slug: c.slug,
      name: c.name,
      iconUrl: null,
      sortOrder: c.sortOrder,
    }));
  }

  const [
    durations,
    cities,
    commissionRate,
    loginHeroImageUrl,
    onb1,
    onb2,
    onb3,
    hb1,
    hb2,
    hb3,
    paymentMethods,
    categoryIconScale,
  ] = await Promise.all([
    getSetting('booking_durations', BOOKING_DURATIONS),
    getSetting('cities', [config.business.defaultCity]),
    getCommissionRate(),
    getSetting('login_hero_image_url', ''),
    getSetting('onboarding_image_1', ''),
    getSetting('onboarding_image_2', ''),
    getSetting('onboarding_image_3', ''),
    getSetting('home_banner_1', ''),
    getSetting('home_banner_2', ''),
    getSetting('home_banner_3', ''),
    getEnabledPaymentMethods(),
    getCategoryIconScale(),
  ]);
  const asUrl = (u) => (typeof u === 'string' ? u : '');

  return ok(res, {
    categories,
    durations: Array.isArray(durations) ? durations : BOOKING_DURATIONS,
    cities: Array.isArray(cities) ? cities : [config.business.defaultCity],
    commissionRate,
    minAge: config.business.minAge,
    placeTypes: ALLOWED_PLACE_TYPES,
    activities: ALLOWED_ACTIVITIES,
    referralReward: config.business.referralReward,
    minPayout: config.business.minPayout,
    currency: 'INR',
    // Admin-editable hero photo for the app login screen ('' = use bundled asset).
    loginHeroImageUrl: asUrl(loginHeroImageUrl),
    // Admin-editable photos for the 3 onboarding steps ('' = use bundled asset).
    onboardingImageUrls: [onb1, onb2, onb3].map(asUrl),
    // Admin-editable promo banners for the home carousel ('' = default card).
    homeBannerImageUrls: [hb1, hb2, hb3].map(asUrl),
    // Admin-toggled payment methods, e.g. { razorpay: true, cash: true }.
    paymentMethods,
    // Admin-controlled home category icon size (0..1 fraction of the tile).
    categoryIconScale,
  });
});

/** GET /meta/health — feature-scoped liveness (the root /health lives in app.js). */
export const health = asyncHandler(async (_req, res) => {
  return ok(res, {
    status: 'ok',
    service: config.appName,
    time: new Date().toISOString(),
  });
});

export default { getConfig, health };
