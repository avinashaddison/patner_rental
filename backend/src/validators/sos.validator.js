// Zod request schemas for the SOS (panic alert) domain.
import { z } from 'zod';

/** POST /sos — raise an emergency alert. */
export const createSosSchema = z.object({
  bookingId: z.string().uuid('Invalid bookingId').optional(),
  latitude: z.coerce.number().min(-90).max(90).optional(),
  longitude: z.coerce.number().min(-180).max(180).optional(),
  message: z.string().trim().max(1000).optional(),
});

/** :id path param for an SOS alert. */
export const sosIdParam = z.object({ id: z.string().uuid('Invalid id') });

export default { createSosSchema, sosIdParam };
