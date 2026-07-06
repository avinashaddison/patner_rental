// Zod request schemas for the companions module.
// Enforces companionship-only safety policy via shared constants where relevant.
import { z } from 'zod';

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/; // HH:mm 24h
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/; // YYYY-MM-DD

const toNum = (v) => (v === undefined || v === '' ? undefined : Number(v));
const toBool = (v) => {
  if (v === undefined || v === '') return undefined;
  if (typeof v === 'boolean') return v;
  return ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
};

/** GET /companions search/list query. */
export const searchCompanionsQuery = z
  .object({
    q: z.string().trim().min(1).max(120).optional(),
    category: z.string().trim().min(1).max(60).optional(),
    interest: z.string().trim().min(1).max(60).optional(),
    city: z.string().trim().min(1).max(80).optional(),
    minRate: z.preprocess(toNum, z.number().nonnegative().optional()),
    maxRate: z.preprocess(toNum, z.number().nonnegative().optional()),
    minRating: z.preprocess(toNum, z.number().min(0).max(5).optional()),
    online: z.preprocess(toBool, z.boolean().optional()),
    featured: z.preprocess(toBool, z.boolean().optional()),
    lat: z.preprocess(toNum, z.number().min(-90).max(90).optional()),
    lng: z.preprocess(toNum, z.number().min(-180).max(180).optional()),
    sort: z.string().trim().max(60).optional(),
    page: z.preprocess(toNum, z.number().int().positive().optional()),
    limit: z.preprocess(toNum, z.number().int().positive().max(100).optional()),
  })
  .passthrough();

/** GET /companions/popular-nearby query. */
export const nearbyQuery = z
  .object({
    lat: z.preprocess(toNum, z.number().min(-90).max(90).optional()),
    lng: z.preprocess(toNum, z.number().min(-180).max(180).optional()),
    limit: z.preprocess(toNum, z.number().int().positive().max(100).optional()),
  })
  .passthrough();

/** GET /companions/:id/availability query. */
export const availabilityQuery = z
  .object({
    date: z
      .string()
      .regex(DATE_RE, 'date must be YYYY-MM-DD')
      .refine((d) => !Number.isNaN(Date.parse(`${d}T00:00:00Z`)), 'invalid date'),
  })
  .passthrough();

/** POST /companions/me — onboard a companion profile. */
export const onboardCompanionBody = z.object({
  aboutMe: z.string().trim().max(2000).optional(),
  languages: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
  interests: z.array(z.string().trim().min(1).max(40)).max(30).optional(),
  hourlyRate: z.coerce.number().nonnegative().max(100000).optional(),
  city: z.string().trim().min(1).max(80).optional(),
  latitude: z.coerce.number().min(-90).max(90).optional(),
  longitude: z.coerce.number().min(-180).max(180).optional(),
  categoryIds: z.array(z.string().uuid()).max(7).optional(),
});

/** PATCH /companions/me — update editable profile fields. */
export const updateCompanionBody = z
  .object({
    aboutMe: z.string().trim().max(2000).optional(),
    languages: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
    interests: z.array(z.string().trim().min(1).max(30)).max(30).optional(),
    hourlyRate: z.coerce.number().nonnegative().max(100000).optional(),
    city: z.string().trim().min(1).max(80).optional(),
    latitude: z.coerce.number().min(-90).max(90).optional(),
    longitude: z.coerce.number().min(-180).max(180).optional(),
    categoryIds: z.array(z.string().uuid()).max(7).optional(),
  })
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });

/** PATCH /companions/me/online */
export const onlineBody = z.object({
  isOnline: z.coerce.boolean(),
});

/** POST /companions/me/photos */
export const addPhotoBody = z.object({
  photoUrl: z.string().url().max(1000),
  isPrimary: z.coerce.boolean().optional(),
});

/** PUT /companions/me/availability */
export const setAvailabilityBody = z.object({
  slots: z
    .array(
      z
        .object({
          dayOfWeek: z.coerce.number().int().min(0).max(6),
          startTime: z.string().regex(TIME_RE, 'startTime must be HH:mm'),
          endTime: z.string().regex(TIME_RE, 'endTime must be HH:mm'),
          isAvailable: z.coerce.boolean().optional(),
        })
        .refine((s) => s.startTime < s.endTime, {
          message: 'startTime must be before endTime',
          path: ['endTime'],
        })
    )
    .max(50),
});

export default {
  searchCompanionsQuery,
  nearbyQuery,
  availabilityQuery,
  onboardCompanionBody,
  updateCompanionBody,
  onlineBody,
  addPhotoBody,
  setAvailabilityBody,
};
