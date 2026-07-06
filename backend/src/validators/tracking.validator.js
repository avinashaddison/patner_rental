// Zod request schemas for live-tracking helpers (Routes API proxy).
import { z } from 'zod';

const point = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
});

/** POST /tracking/route — compute a route + ETA between two points. */
export const routeSchema = z.object({
  bookingId: z.string().uuid('Invalid bookingId'),
  origin: point,
  destination: point,
  // Google Routes travel modes. DRIVE is the sensible default; TWO_WHEELER is
  // common in India for short hops.
  mode: z.enum(['DRIVE', 'TWO_WHEELER', 'WALK', 'BICYCLE']).optional(),
});

/** GET /tracking/places/autocomplete — typed place search. */
export const autocompleteSchema = z.object({
  q: z.string().trim().min(2, 'Type at least 2 characters').max(200),
  session: z.string().max(100).optional(),
});

/** GET /tracking/places/details — resolve a placeId to coordinates. */
export const placeDetailsSchema = z.object({
  placeId: z.string().min(1).max(400),
  session: z.string().max(100).optional(),
});

/** GET /tracking/geocode/reverse — coordinates to address. */
export const reverseGeocodeSchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
});

export default {
  routeSchema,
  autocompleteSchema,
  placeDetailsSchema,
  reverseGeocodeSchema,
};
