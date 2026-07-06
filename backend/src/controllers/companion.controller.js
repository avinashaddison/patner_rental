// HTTP handlers for the companion dashboard. All routes are companion-only.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok } from '../utils/apiResponse.js';
import * as companion from '../services/companion.service.js';

/** GET /companion/dashboard */
export const dashboard = asyncHandler(async (req, res) => {
  const data = await companion.getDashboard(req.user);
  return ok(res, data);
});

/** GET /companion/earnings */
export const earnings = asyncHandler(async (req, res) => {
  const { meta, ...data } = await companion.getEarnings(req.user, req);
  return ok(res, data, meta);
});

/** GET /companion/bookings */
export const bookings = asyncHandler(async (req, res) => {
  const { items, meta } = await companion.getReceivedBookings(req.user, req, {
    status: req.query.status,
  });
  return ok(res, items, meta);
});

/** PATCH /companion/location — set the companion's base coordinates. */
export const updateLocation = asyncHandler(async (req, res) => {
  const data = await companion.updateLocation(req.user, {
    latitude: req.body.latitude,
    longitude: req.body.longitude,
  });
  return ok(res, data);
});

export default { dashboard, earnings, bookings, updateLocation };
