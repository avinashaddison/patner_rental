// Zod request schemas for the companion (self) dashboard domain.
import { z } from 'zod';

/** PATCH /companion/location — set the companion's base coordinates. */
export const updateLocationSchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
});

export default { updateLocationSchema };
