// Zod request schemas for the reviews module.
import { z } from 'zod';

const rating = z.coerce.number().int().min(1).max(5);

/** POST /reviews */
export const createReviewBody = z.object({
  bookingId: z.string().uuid(),
  behaviourRating: rating,
  communicationRating: rating,
  punctualityRating: rating,
  comment: z.string().trim().max(2000).optional(),
});

/** GET /reviews/companion/:companionId */
export const companionIdParam = z.object({
  companionId: z.string().uuid(),
});

export default { createReviewBody, companionIdParam };
