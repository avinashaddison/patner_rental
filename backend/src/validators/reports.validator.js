// Zod request schemas for the reports / safety domain.
import { z } from 'zod';

const REPORT_CATEGORIES = ['HARASSMENT', 'FAKE_PROFILE', 'ABUSE', 'SPAM', 'OTHER'];

/** POST /reports — file a complaint against another user. */
export const createReportSchema = z.object({
  reportedUserId: z.string().uuid('Invalid reportedUserId'),
  bookingId: z.string().uuid('Invalid bookingId').optional(),
  category: z.enum(REPORT_CATEGORIES),
  description: z.string().trim().max(2000).optional(),
});

export default { createReportSchema, REPORT_CATEGORIES };
