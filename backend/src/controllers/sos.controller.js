// Thin HTTP handlers for the SOS domain.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import * as sosService from '../services/sos.service.js';

/** POST /sos — raise an emergency alert. */
export const create = asyncHandler(async (req, res) => {
  const alert = await sosService.createAlert({
    user: req.user,
    bookingId: req.body.bookingId,
    latitude: req.body.latitude,
    longitude: req.body.longitude,
    message: req.body.message,
  });
  return created(res, alert);
});

/** GET /sos/active — the user's active alerts. */
export const listActive = asyncHandler(async (req, res) => {
  const alerts = await sosService.listActive(req.user.id);
  return ok(res, alerts);
});

/** POST /sos/:id/cancel — cancel an active alert. */
export const cancel = asyncHandler(async (req, res) => {
  const alert = await sosService.cancelAlert({ sosId: req.params.id, user: req.user });
  return ok(res, alert);
});

export default { create, listActive, cancel };
