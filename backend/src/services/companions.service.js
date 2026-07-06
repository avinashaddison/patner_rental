// Companions business logic: search/list, profiles, availability slot computation,
// companion-self onboarding + profile/photo/availability management.
//
// Safety policy enforced here:
//  - Only companions with status=APPROVED *and* approved KYC (GOVERNMENT_ID + SELFIE)
//    are publicly listed / discoverable.
//  - Companionship-only, public-place-only meetings are enforced at booking time
//    (bookings module); this module surfaces availability windows only.
import dayjs from 'dayjs';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { discoveryGenderFor } from '../utils/discovery.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import { BOOKING_DURATIONS } from '../config/constants.js';

// Booking states that still occupy a companion's time slot for a given day.
const ACTIVE_BOOKING_STATES = ['PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED'];

const num = (v) => (v == null ? null : Number(v));

/**
 * Whether a companion's KYC is fully approved (both GOVERNMENT_ID and SELFIE).
 * @param {string} userId
 * @param {object} [client]
 */
export async function isKycApproved(userId, client = prisma) {
  const approved = await client.kycDocument.findMany({
    where: { userId, status: 'APPROVED' },
    select: { docType: true },
  });
  const types = new Set(approved.map((d) => d.docType));
  return types.has('GOVERNMENT_ID') && types.has('SELFIE');
}

/** Compute derived age (years) from a user's dateOfBirth. */
export function ageFromDob(dateOfBirth) {
  if (!dateOfBirth) return null;
  const years = dayjs().diff(dayjs(dateOfBirth), 'year');
  return Number.isFinite(years) ? years : null;
}

/** Haversine distance in kilometers between two lat/lng points. */
export function haversineKm(lat1, lng1, lat2, lng2) {
  if ([lat1, lng1, lat2, lng2].some((v) => v == null || Number.isNaN(Number(v)))) return null;
  const R = 6371; // km
  const toRad = (d) => (Number(d) * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 10) / 10;
}

// Prisma include that loads everything needed to build a card or profile.
const cardInclude = {
  user: {
    select: { fullName: true, username: true, dateOfBirth: true, profilePhotoUrl: true, kycDocuments: { select: { docType: true, status: true } } },
  },
  photos: { orderBy: [{ isPrimary: 'desc' }, { sortOrder: 'asc' }] },
  categories: { include: { category: { select: { slug: true } } } },
};

function kycApprovedFromUser(user) {
  const docs = user?.kycDocuments || [];
  const approved = new Set(docs.filter((d) => d.status === 'APPROVED').map((d) => d.docType));
  return approved.has('GOVERNMENT_ID') && approved.has('SELFIE');
}

/**
 * Build the public "companion card" shape (see API.md).
 * @param {object} companion  must be loaded with `cardInclude`
 * @param {{lat?:number, lng?:number}} [viewer]  optional viewer location for distanceKm
 */
export function toCard(companion, viewer = {}) {
  const primary =
    (companion.photos || []).find((p) => p.isPrimary) || (companion.photos || [])[0] || null;
  const photoUrl = primary?.photoUrl || companion.user?.profilePhotoUrl || null;
  const distanceKm =
    viewer.lat != null && viewer.lng != null
      ? haversineKm(viewer.lat, viewer.lng, companion.latitude, companion.longitude)
      : null;

  return {
    id: companion.id,
    name: companion.user?.fullName || null,
    username: companion.user?.username || null,
    age: ageFromDob(companion.user?.dateOfBirth),
    city: companion.city,
    photoUrl,
    rating: num(companion.ratingAvg) ?? 0,
    ratingCount: companion.ratingCount,
    hourlyRate: num(companion.hourlyRate) ?? 0,
    isVerified: companion.status === 'APPROVED' && kycApprovedFromUser(companion.user),
    isOnline: companion.isOnline,
    isFeatured: companion.isFeatured,
    categories: (companion.categories || []).map((c) => c.category.slug),
    distanceKm,
  };
}

/**
 * Build the full companion profile shape: photos, availability, recent reviews,
 * isVerified flag, categories.
 * @param {object} companion  loaded with `fullInclude`
 */
export function toProfile(companion, viewer = {}) {
  const card = toCard(companion, viewer);
  return {
    ...card,
    // The companion's user id — needed by the client to Report/Block them.
    userId: companion.userId,
    aboutMe: companion.aboutMe || null,
    languages: companion.languages || [],
    interests: companion.interests || [],
    latitude: companion.latitude ?? null,
    longitude: companion.longitude ?? null,
    totalBookings: companion.totalBookings,
    followerCount: companion.followerCount ?? 0,
    postCount: companion.postCount ?? 0,
    isFollowing: false, // overwritten by getPublicProfile when a viewer is known
    status: companion.status,
    photos: (companion.photos || []).map((p) => ({
      id: p.id,
      photoUrl: p.photoUrl,
      isPrimary: p.isPrimary,
      sortOrder: p.sortOrder,
    })),
    categoryDetails: (companion.categories || []).map((c) => ({
      id: c.category.id,
      slug: c.category.slug,
      name: c.category.name,
    })),
    availability: (companion.availability || []).map((a) => ({
      id: a.id,
      dayOfWeek: a.dayOfWeek,
      startTime: a.startTime,
      endTime: a.endTime,
      isAvailable: a.isAvailable,
    })),
    recentReviews: (companion.reviews || []).map(reviewToDto),
    createdAt: companion.createdAt,
  };
}

/** Map a Review row (with customer) to API DTO. */
export function reviewToDto(r) {
  return {
    id: r.id,
    bookingId: r.bookingId,
    behaviourRating: r.behaviourRating,
    communicationRating: r.communicationRating,
    punctualityRating: r.punctualityRating,
    overallRating: num(r.overallRating),
    comment: r.comment || null,
    createdAt: r.createdAt,
    customer: r.customer
      ? { id: r.customer.id, name: r.customer.fullName || 'User', photoUrl: r.customer.profilePhotoUrl || null }
      : null,
  };
}

// Base WHERE clause that keeps only publicly-listable companions:
// APPROVED status + both KYC docs approved.
function listableWhere(extra = {}, viewer = null) {
  const gender = discoveryGenderFor(viewer);
  return {
    status: 'APPROVED',
    user: {
      isBlocked: false,
      ...(gender ? { gender } : {}),
      kycDocuments: { some: { docType: 'GOVERNMENT_ID', status: 'APPROVED' } },
      AND: [{ kycDocuments: { some: { docType: 'SELFIE', status: 'APPROVED' } } }],
    },
    ...extra,
  };
}

/**
 * Search / list companions with filters, pagination, sort. Returns { items, meta }.
 */
export async function searchCompanions(query, viewerUser = null) {
  const { skip, take, page, limit } = getPagination({ query });

  const and = [];
  if (query.q) {
    and.push({ user: { fullName: { contains: query.q, mode: 'insensitive' } } });
  }
  if (query.category) {
    and.push({ categories: { some: { category: { slug: query.category } } } });
  }
  if (query.interest) {
    and.push({ interests: { has: query.interest } });
  }
  if (query.city) {
    and.push({ city: { equals: query.city, mode: 'insensitive' } });
  }
  if (query.minRate != null || query.maxRate != null) {
    const rate = {};
    if (query.minRate != null) rate.gte = query.minRate;
    if (query.maxRate != null) rate.lte = query.maxRate;
    and.push({ hourlyRate: rate });
  }
  if (query.minRating != null) {
    and.push({ ratingAvg: { gte: query.minRating } });
  }
  if (query.online === true) and.push({ isOnline: true });
  if (query.featured === true) and.push({ isFeatured: true });

  const where = listableWhere(and.length ? { AND: and } : {}, viewerUser);

  // Sort. Allowlist sortable columns; default: featured first, then rating, then recent.
  const orderBy = buildOrderBy(query.sort);

  const [rows, total] = await Promise.all([
    prisma.companion.findMany({ where, include: cardInclude, orderBy, skip, take }),
    prisma.companion.count({ where }),
  ]);

  const viewer = { lat: query.lat, lng: query.lng };
  let items = rows.map((c) => toCard(c, viewer));

  // If a viewer location was provided and sort=distance, order by computed distance.
  if (query.sort === 'distance' && query.lat != null && query.lng != null) {
    items = items.sort((a, b) => (a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity));
  }

  return { items, meta: buildMeta(total, page, limit) };
}

const SORTABLE = new Set(['ratingAvg', 'hourlyRate', 'createdAt', 'totalBookings']);

function buildOrderBy(sort) {
  if (sort && sort !== 'distance') {
    const [field, dirRaw] = String(sort).split(':');
    const dir = String(dirRaw).toLowerCase() === 'asc' ? 'asc' : 'desc';
    if (SORTABLE.has(field)) {
      return [{ [field]: dir }, { createdAt: 'desc' }];
    }
  }
  return [{ isFeatured: 'desc' }, { ratingAvg: 'desc' }, { ratingCount: 'desc' }, { createdAt: 'desc' }];
}

/** Featured companions (listable + isFeatured), optionally filtered by city. */
export async function listFeatured(query = {}, viewerUser = null) {
  const { skip, take, page, limit } = getPagination({ query });
  const extra = { isFeatured: true };
  if (query.city) {
    extra.city = { equals: query.city, mode: 'insensitive' };
  }
  const where = listableWhere(extra, viewerUser);
  const [rows, total] = await Promise.all([
    prisma.companion.findMany({
      where,
      include: cardInclude,
      orderBy: [{ ratingAvg: 'desc' }, { ratingCount: 'desc' }],
      skip,
      take,
    }),
    prisma.companion.count({ where }),
  ]);
  const viewer = { lat: query.lat, lng: query.lng };
  return { items: rows.map((c) => toCard(c, viewer)), meta: buildMeta(total, page, limit) };
}

/**
 * Popular nearby: rank listable companions by distance (if lat/lng given) then rating.
 */
export async function popularNearby({ lat, lng, city, limit = 20 } = {}, viewerUser = null) {
  const take = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 100);
  const extra = {};
  if (city) {
    extra.city = { equals: city, mode: 'insensitive' };
  }
  const where = listableWhere(extra, viewerUser);
  const rows = await prisma.companion.findMany({
    where,
    include: cardInclude,
    orderBy: [{ ratingAvg: 'desc' }, { ratingCount: 'desc' }, { totalBookings: 'desc' }],
    take: lat != null && lng != null ? 200 : take, // fetch a wider set to sort by distance
  });

  let cards = rows.map((c) => toCard(c, { lat, lng }));
  if (lat != null && lng != null) {
    cards = cards
      .sort((a, b) => {
        const da = a.distanceKm ?? Infinity;
        const db = b.distanceKm ?? Infinity;
        if (da !== db) return da - db;
        return (b.rating ?? 0) - (a.rating ?? 0);
      })
      .slice(0, take);
  }
  return cards;
}

/** Active category list. */
export async function listCategories() {
  const cats = await prisma.category.findMany({
    where: { isActive: true },
    orderBy: { sortOrder: 'asc' },
  });
  return cats.map((c) => ({
    id: c.id,
    slug: c.slug,
    name: c.name,
    iconUrl: c.iconUrl || null,
    sortOrder: c.sortOrder,
  }));
}

const fullInclude = {
  ...cardInclude,
  availability: { orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }] },
  reviews: {
    orderBy: { createdAt: 'desc' },
    take: 5,
    include: { customer: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
  },
};

// Profile include needs category id+name too (cardInclude only selects slug).
const fullIncludeWithCatNames = {
  user: cardInclude.user,
  photos: cardInclude.photos,
  categories: { include: { category: { select: { id: true, slug: true, name: true } } } },
  availability: fullInclude.availability,
  reviews: fullInclude.reviews,
};

/**
 * Full public profile by id. Only listable companions are exposed publicly,
 * EXCEPT when `allowSelf` matches (companion viewing self) — not used here.
 */
export async function getPublicProfile(id, viewer = {}) {
  const companion = await prisma.companion.findUnique({
    where: { id },
    include: fullIncludeWithCatNames,
  });
  if (!companion) throw ApiError.notFound('Companion not found');

  const kycOk = kycApprovedFromUser(companion.user);
  if (companion.status !== 'APPROVED' || !kycOk) {
    // Don't leak unapproved/suspended profiles publicly.
    throw ApiError.notFound('Companion not found');
  }
  const profile = toProfile(companion, viewer);
  // Total hearts across all published posts — shown on the profile.
  const likeAgg = await prisma.post.aggregate({
    _sum: { likeCount: true },
    where: { companionId: id, status: 'PUBLISHED' },
  });
  profile.totalLikes = likeAgg._sum.likeCount ?? 0;
  // Resolve the viewer's follow state for this companion (if signed in).
  if (viewer.userId) {
    const follow = await prisma.follow.findUnique({
      where: { followerId_companionId: { followerId: viewer.userId, companionId: id } },
      select: { id: true },
    });
    profile.isFollowing = Boolean(follow);
  }
  return profile;
}

/**
 * Compute free time slots for a companion on a given date.
 * Slots are derived from the weekly availability window for that weekday, sliced
 * into 1-hour starts, minus any starts already occupied by active bookings.
 * Past slots (for "today") are excluded.
 * @param {string} companionId
 * @param {string} dateStr  YYYY-MM-DD
 */
export async function getAvailableSlots(companionId, dateStr) {
  const companion = await prisma.companion.findUnique({ where: { id: companionId } });
  if (!companion) throw ApiError.notFound('Companion not found');

  const date = dayjs(`${dateStr}T00:00:00`);
  if (!date.isValid()) throw ApiError.badRequest('Invalid date');
  const dayOfWeek = date.day(); // 0=Sun..6=Sat

  const windows = await prisma.companionAvailability.findMany({
    where: { companionId, dayOfWeek, isAvailable: true },
    orderBy: { startTime: 'asc' },
  });

  // Existing bookings for that date that occupy time.
  const dayStart = date.startOf('day').toDate();
  const dayEnd = date.endOf('day').toDate();
  const bookings = await prisma.booking.findMany({
    where: {
      companionId,
      status: { in: ACTIVE_BOOKING_STATES },
      bookingDate: { gte: dayStart, lte: dayEnd },
    },
    select: { startTime: true, endTime: true, durationHours: true },
  });

  const booked = bookings.map((b) => ({
    start: toMinutes(b.startTime),
    end: toMinutes(b.endTime),
  }));

  const now = dayjs();
  const isToday = date.isSame(now, 'day');
  const nowMinutes = now.hour() * 60 + now.minute();

  const slots = [];
  for (const w of windows) {
    const wStart = toMinutes(w.startTime);
    const wEnd = toMinutes(w.endTime);
    // 1-hour granularity starts within the window (leave room for at least 1h).
    for (let s = wStart; s + 60 <= wEnd; s += 60) {
      const slotStart = s;
      const slotEnd = s + 60;
      if (isToday && slotStart <= nowMinutes) continue; // skip past slots today
      const overlaps = booked.some((b) => slotStart < b.end && slotEnd > b.start);
      if (overlaps) continue;

      // The max contiguous free duration starting here (capped to allowed durations).
      const maxFree = maxFreeHours(slotStart, wEnd, booked);
      const availableDurations = BOOKING_DURATIONS.filter((h) => h <= maxFree);

      slots.push({
        startTime: toHHmm(slotStart),
        endTime: toHHmm(slotEnd),
        availableDurations,
      });
    }
  }

  return {
    companionId,
    date: dateStr,
    dayOfWeek,
    slots,
  };
}

function maxFreeHours(slotStart, windowEnd, booked) {
  // Walk forward in 1-hour increments until we hit a booking or the window end.
  let hours = 0;
  let cursor = slotStart;
  while (cursor + 60 <= windowEnd) {
    const cStart = cursor;
    const cEnd = cursor + 60;
    const blocked = booked.some((b) => cStart < b.end && cEnd > b.start);
    if (blocked) break;
    hours += 1;
    cursor += 60;
  }
  return hours;
}

function toMinutes(hhmm) {
  const [h, m] = String(hhmm).split(':').map((n) => parseInt(n, 10));
  return (h || 0) * 60 + (m || 0);
}

function toHHmm(minutes) {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** Paginated reviews for a companion (public). */
export async function listCompanionReviews(companionId, query = {}) {
  const companion = await prisma.companion.findUnique({ where: { id: companionId }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion not found');

  const { skip, take, page, limit } = getPagination({ query });
  const where = { companionId };
  const [rows, total] = await Promise.all([
    prisma.review.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      include: { customer: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
    }),
    prisma.review.count({ where }),
  ]);
  return { items: rows.map(reviewToDto), meta: buildMeta(total, page, limit) };
}

// ----------------------------------------------------------------------------
// Companion-self management
// ----------------------------------------------------------------------------

/** Load the companion row for a user, throwing 404 if absent. */
async function requireOwnCompanion(userId) {
  const companion = await prisma.companion.findUnique({
    where: { userId },
    include: fullIncludeWithCatNames,
  });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');
  return companion;
}

/**
 * Onboard / create the companion profile for the authenticated COMPANION user.
 * Idempotent-ish: if a profile already exists, returns CONFLICT.
 */
export async function onboardCompanion(user, body) {
  const existing = await prisma.companion.findUnique({ where: { userId: user.id } });
  if (existing) throw ApiError.conflict('Companion profile already exists');

  const city = body.city || user.city || 'Ranchi';

  const created = await prisma.$transaction(async (tx) => {
    const companion = await tx.companion.create({
      data: {
        userId: user.id,
        aboutMe: body.aboutMe ?? null,
        languages: body.languages ?? [],
        interests: body.interests ?? [],
        hourlyRate: body.hourlyRate ?? 0,
        city,
        latitude: body.latitude ?? null,
        longitude: body.longitude ?? null,
        status: 'PENDING',
      },
    });

    if (body.categoryIds?.length) {
      await setCategories(tx, companion.id, body.categoryIds);
    }

    // "Become a Companion" from a customer account: upgrade the role now that a
    // companion profile exists. requireAuth reloads the user per request, so the
    // rest of onboarding (photos, KYC) passes the COMPANION gate immediately.
    if (user.role !== 'COMPANION') {
      await tx.user.update({ where: { id: user.id }, data: { role: 'COMPANION' } });
    }

    // Ensure a wallet exists for the companion.
    await tx.wallet.upsert({ where: { userId: user.id }, create: { userId: user.id }, update: {} });
    return companion;
  });

  return loadProfileById(created.id);
}

/** Replace a companion's category links with the given category ids. */
async function setCategories(tx, companionId, categoryIds) {
  const unique = [...new Set(categoryIds)];
  // Validate the categories exist + are active.
  const valid = await tx.category.findMany({
    where: { id: { in: unique }, isActive: true },
    select: { id: true },
  });
  const validIds = new Set(valid.map((c) => c.id));
  const missing = unique.filter((id) => !validIds.has(id));
  if (missing.length) throw ApiError.badRequest('Unknown or inactive category', missing);

  await tx.companionCategory.deleteMany({ where: { companionId } });
  if (unique.length) {
    await tx.companionCategory.createMany({
      data: unique.map((categoryId) => ({ companionId, categoryId })),
      skipDuplicates: true,
    });
  }
}

async function loadProfileById(id) {
  const companion = await prisma.companion.findUnique({ where: { id }, include: fullIncludeWithCatNames });
  return toProfile(companion);
}

/** Own profile for the authenticated companion. */
export async function getOwnProfile(user) {
  const companion = await requireOwnCompanion(user.id);
  const profile = toProfile(companion);
  // How many companions this user follows (their own "following" count).
  profile.followingCount = await prisma.follow.count({ where: { followerId: user.id } });
  return profile;
}

/** Update editable profile fields. */
export async function updateOwnProfile(user, body) {
  const companion = await prisma.companion.findUnique({ where: { userId: user.id } });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');

  const data = {};
  if (body.aboutMe !== undefined) data.aboutMe = body.aboutMe;
  if (body.languages !== undefined) data.languages = body.languages;
  if (body.interests !== undefined) data.interests = body.interests;
  if (body.hourlyRate !== undefined) data.hourlyRate = body.hourlyRate;
  if (body.city !== undefined) data.city = body.city;
  if (body.latitude !== undefined) data.latitude = body.latitude;
  if (body.longitude !== undefined) data.longitude = body.longitude;

  await prisma.$transaction(async (tx) => {
    if (Object.keys(data).length) {
      await tx.companion.update({ where: { id: companion.id }, data });
    }
    if (body.categoryIds !== undefined) {
      await setCategories(tx, companion.id, body.categoryIds);
    }
  });

  return loadProfileById(companion.id);
}

/** Toggle online presence. */
export async function setOnline(user, isOnline) {
  const companion = await prisma.companion.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');
  const updated = await prisma.companion.update({
    where: { id: companion.id },
    data: { isOnline: Boolean(isOnline) },
    select: { id: true, isOnline: true },
  });
  return { id: updated.id, isOnline: updated.isOnline };
}

/** Add a photo to the companion gallery. */
export async function addPhoto(user, { photoUrl, isPrimary = false }) {
  const companion = await prisma.companion.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');

  const count = await prisma.companionPhoto.count({ where: { companionId: companion.id } });
  if (count >= 10) throw ApiError.badRequest('Photo limit (10) reached');

  // First photo is primary by default.
  const makePrimary = isPrimary || count === 0;

  const photo = await prisma.$transaction(async (tx) => {
    if (makePrimary) {
      await tx.companionPhoto.updateMany({ where: { companionId: companion.id }, data: { isPrimary: false } });
    }
    return tx.companionPhoto.create({
      data: {
        companionId: companion.id,
        photoUrl,
        isPrimary: makePrimary,
        sortOrder: count,
      },
    });
  });

  return { id: photo.id, photoUrl: photo.photoUrl, isPrimary: photo.isPrimary, sortOrder: photo.sortOrder };
}

/** Delete a photo the companion owns. */
export async function deletePhoto(user, photoId) {
  const companion = await prisma.companion.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');

  const photo = await prisma.companionPhoto.findUnique({ where: { id: photoId } });
  if (!photo || photo.companionId !== companion.id) throw ApiError.notFound('Photo not found');

  await prisma.$transaction(async (tx) => {
    await tx.companionPhoto.delete({ where: { id: photoId } });
    if (photo.isPrimary) {
      // Promote the next photo (lowest sortOrder) to primary.
      const next = await tx.companionPhoto.findFirst({
        where: { companionId: companion.id },
        orderBy: { sortOrder: 'asc' },
      });
      if (next) {
        await tx.companionPhoto.update({ where: { id: next.id }, data: { isPrimary: true } });
      }
    }
  });

  return { deleted: true };
}

/** Replace the weekly availability with the provided slots. */
export async function setAvailability(user, slots) {
  const companion = await prisma.companion.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion profile not found. Onboard first.');

  const rows = await prisma.$transaction(async (tx) => {
    await tx.companionAvailability.deleteMany({ where: { companionId: companion.id } });
    if (slots.length) {
      await tx.companionAvailability.createMany({
        data: slots.map((s) => ({
          companionId: companion.id,
          dayOfWeek: s.dayOfWeek,
          startTime: s.startTime,
          endTime: s.endTime,
          isAvailable: s.isAvailable ?? true,
        })),
      });
    }
    return tx.companionAvailability.findMany({
      where: { companionId: companion.id },
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }],
    });
  });

  return rows.map((a) => ({
    id: a.id,
    dayOfWeek: a.dayOfWeek,
    startTime: a.startTime,
    endTime: a.endTime,
    isAvailable: a.isAvailable,
  }));
}

export default {
  isKycApproved,
  ageFromDob,
  haversineKm,
  toCard,
  toProfile,
  reviewToDto,
  searchCompanions,
  listFeatured,
  popularNearby,
  listCategories,
  getPublicProfile,
  getAvailableSlots,
  listCompanionReviews,
  onboardCompanion,
  getOwnProfile,
  updateOwnProfile,
  setOnline,
  addPhoto,
  deletePhoto,
  setAvailability,
};
