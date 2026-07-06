// Thin HTTP handlers for live-tracking helpers.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok } from '../utils/apiResponse.js';
import * as trackingService from '../services/tracking.service.js';

/** POST /tracking/route — route + ETA between two booking parties. */
export const route = asyncHandler(async (req, res) => {
  const result = await trackingService.computeRoute({
    user: req.user,
    bookingId: req.body.bookingId,
    origin: req.body.origin,
    destination: req.body.destination,
    mode: req.body.mode,
  });
  return ok(res, { route: result });
});

/** GET /tracking/places/autocomplete — typed place search (Ranchi-biased). */
export const placesAutocomplete = asyncHandler(async (req, res) => {
  const suggestions = await trackingService.placesAutocomplete({
    query: req.query.q,
    sessionToken: req.query.session,
  });
  return ok(res, { suggestions });
});

/** GET /tracking/places/details — resolve a placeId to coordinates. */
export const placeDetails = asyncHandler(async (req, res) => {
  const place = await trackingService.placeDetails({
    placeId: req.query.placeId,
    sessionToken: req.query.session,
  });
  return ok(res, { place });
});

/** GET /tracking/geocode/reverse — coordinates to a human address. */
export const reverseGeocode = asyncHandler(async (req, res) => {
  const address = await trackingService.reverseGeocode({
    lat: req.query.lat,
    lng: req.query.lng,
  });
  return ok(res, { address });
});

export default { route, placesAutocomplete, placeDetails, reverseGeocode };
