// Zod request schemas for the notifications domain.
import { z } from 'zod';

/** :id path param for a notification. */
export const notificationIdParam = z.object({ id: z.string().uuid('Invalid id') });

export default { notificationIdParam };
