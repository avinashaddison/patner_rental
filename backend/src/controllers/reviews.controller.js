// Thin HTTP handlers for the reviews module.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import * as reviewService from '../services/reviews.service.js';

export const create = asyncHandler(async (req, res) => {
  const review = await reviewService.createReview(req.user, req.body);
  return created(res, review);
});

export const listForCompanion = asyncHandler(async (req, res) => {
  const { items, meta } = await reviewService.listForCompanion(req.params.companionId, req.query);
  return ok(res, items, meta);
});

export default { create, listForCompanion };
