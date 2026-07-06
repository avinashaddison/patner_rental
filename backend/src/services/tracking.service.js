// Live-tracking helpers. Proxies Mapbox's Directions + Geocoding APIs so the
// token never reaches the client, and so we can authorise the caller as a
// booking participant before spending an API call.
//
// Gracefully degrades: if no MAPBOX_TOKEN is configured (or Mapbox errors),
// computeRoute returns null and the client just omits the route line;
// autocomplete returns [] and the field becomes a plain text input.
import { config } from '../config/index.js';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';

const DIRECTIONS_BASE = 'https://api.mapbox.com/directions/v5/mapbox';
const GEOCODE_BASE = 'https://api.mapbox.com/geocoding/v5/mapbox.places';
// Search Box API — much richer Indian POI coverage than geocoding v5
// ("Mall of Ranchi" finds the actual mall instead of a fuzzy far-away match).
const SEARCHBOX_BASE = 'https://api.mapbox.com/search/searchbox/v1';

// Ranchi city centre — autocomplete/proximity bias.
const RANCHI = { lat: 23.3441, lng: 85.3096 };

/** Map our travel modes to a Mapbox routing profile. */
function mapboxProfile(mode) {
  switch (mode) {
    case 'WALK':
      return 'walking';
    case 'BICYCLE':
      return 'cycling';
    case 'DRIVE':
    case 'TWO_WHEELER':
    default:
      return 'driving';
  }
}

/** Throw unless the user is a participant of the booking. */
async function assertBookingParticipant(bookingId, userId) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: {
      id: true,
      customerId: true,
      companion: { select: { userId: true } },
    },
  });
  if (!booking) throw ApiError.notFound('Booking not found');
  const isParticipant =
    booking.customerId === userId || booking.companion?.userId === userId;
  if (!isParticipant) {
    throw ApiError.forbidden('You are not a participant of this booking');
  }
}

/**
 * Compute a route + ETA between two points for a booking participant.
 * Returns `{ encodedPolyline, distanceMeters, durationSeconds }` or null when
 * Mapbox is not configured / could not produce a route. Mapbox's
 * `geometries=polyline` uses precision 5 — identical to Google's encoded
 * polyline — so the mobile decoder is unchanged.
 */
export async function computeRoute({
  user,
  bookingId,
  origin,
  destination,
  mode = 'DRIVE',
}) {
  await assertBookingParticipant(bookingId, user.id);

  const token = config.maps.mapboxToken;
  if (!token) return null; // Mapbox not configured — client omits the route line.

  const profile = mapboxProfile(mode);
  // Mapbox coordinate order is lng,lat.
  const coords =
    `${origin.lng},${origin.lat};${destination.lng},${destination.lat}`;

  try {
    const url = new URL(`${DIRECTIONS_BASE}/${profile}/${coords}`);
    url.searchParams.set('geometries', 'polyline');
    url.searchParams.set('overview', 'full');
    url.searchParams.set('access_token', token);

    const res = await fetch(url);
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      logger.warn(
        `[routes] Mapbox Directions ${res.status}: ${text.slice(0, 200)}`,
      );
      return null;
    }

    const json = await res.json();
    const route = json.routes?.[0];
    if (!route) return null;

    return {
      encodedPolyline: route.geometry ?? null, // encoded polyline, precision 5
      distanceMeters:
        route.distance != null ? Math.round(route.distance) : null,
      durationSeconds:
        route.duration != null ? Math.round(route.duration) : null,
    };
  } catch (err) {
    logger.warn(`[routes] computeRoute failed: ${err.message}`);
    return null;
  }
}

// --- Place search proxies ----------------------------------------------------
// The Search Box API powers the meeting-place autocomplete (suggest →
// retrieve, tied by a session token). The placeId we hand the client is an
// opaque base64 blob carrying whatever retrieve needs. Biased to Ranchi so
// suggestions are local.

function encodePlaceId(detail) {
  return Buffer.from(JSON.stringify(detail), 'utf8').toString('base64url');
}

/**
 * Place autocomplete for a typed query (Search Box `/suggest`). Returns an
 * array of `{ placeId, primary, secondary }` (possibly empty). The `placeId`
 * is an opaque token carrying the Search Box mapbox_id + session, which
 * placeDetails resolves via `/retrieve` (same session → billed as one).
 */
export async function placesAutocomplete({ query, sessionToken }) {
  const token = config.maps.mapboxToken;
  if (!token || !query || query.trim().length < 2) return [];
  const session = sessionToken || `srv_${Date.now()}`;
  try {
    const url = new URL(`${SEARCHBOX_BASE}/suggest`);
    url.searchParams.set('q', query.trim());
    url.searchParams.set('access_token', token);
    url.searchParams.set('session_token', session);
    url.searchParams.set('country', 'in');
    url.searchParams.set('proximity', `${RANCHI.lng},${RANCHI.lat}`);
    url.searchParams.set('limit', '6');
    url.searchParams.set('language', 'en');

    const res = await fetch(url);
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      logger.warn(`[places] autocomplete ${res.status}: ${text.slice(0, 200)}`);
      return [];
    }
    const json = await res.json();
    return (json.suggestions ?? [])
      .filter((s) => s.mapbox_id && s.name)
      .map((s) => ({
        placeId: encodePlaceId({ mapboxId: s.mapbox_id, session }),
        primary: s.name,
        secondary: s.place_formatted ?? s.full_address ?? s.address ?? '',
      }));
  } catch (err) {
    logger.warn(`[places] autocomplete failed: ${err.message}`);
    return [];
  }
}

/**
 * Resolve a placeId to `{ name, address, lat, lng }` (or null).
 * New-format ids carry a Search Box mapbox_id and are resolved via
 * `/retrieve`; legacy ids already embed coordinates and decode locally.
 */
export async function placeDetails({ placeId, sessionToken }) {
  if (!placeId) return null;
  let detail;
  try {
    detail = JSON.parse(Buffer.from(placeId, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  // Legacy geocoding-v5 token — coordinates inline, no network needed.
  if (Number.isFinite(detail?.lat) && Number.isFinite(detail?.lng)) {
    return {
      name: detail.name || '',
      address: detail.address || '',
      lat: detail.lat,
      lng: detail.lng,
    };
  }

  const token = config.maps.mapboxToken;
  if (!token || !detail?.mapboxId) return null;
  try {
    const url = new URL(
      `${SEARCHBOX_BASE}/retrieve/${encodeURIComponent(detail.mapboxId)}`,
    );
    url.searchParams.set('access_token', token);
    url.searchParams.set(
      'session_token',
      detail.session || sessionToken || `srv_${Date.now()}`,
    );

    const res = await fetch(url);
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      logger.warn(`[places] retrieve ${res.status}: ${text.slice(0, 200)}`);
      return null;
    }
    const json = await res.json();
    const f = json.features?.[0];
    const props = f?.properties ?? {};
    const lat = props.coordinates?.latitude ?? f?.geometry?.coordinates?.[1];
    const lng = props.coordinates?.longitude ?? f?.geometry?.coordinates?.[0];
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return {
      name: props.name || '',
      address: props.full_address || props.place_formatted || props.name || '',
      lat,
      lng,
    };
  } catch (err) {
    logger.warn(`[places] retrieve failed: ${err.message}`);
    return null;
  }
}

/**
 * Reverse-geocode coordinates to a human address string (or null).
 */
export async function reverseGeocode({ lat, lng }) {
  const token = config.maps.mapboxToken;
  if (!token) return null;
  try {
    const url = new URL(`${GEOCODE_BASE}/${lng},${lat}.json`);
    url.searchParams.set('access_token', token);
    url.searchParams.set('limit', '1');
    const res = await fetch(url);
    if (!res.ok) return null;
    const json = await res.json();
    return json.features?.[0]?.place_name ?? null;
  } catch (err) {
    logger.warn(`[geocode] reverse failed: ${err.message}`);
    return null;
  }
}

export default { computeRoute, placesAutocomplete, placeDetails, reverseGeocode };
