// Zod request schemas for the referrals domain.
import { z } from 'zod';

/** POST /referrals/apply — apply a referrer's code during onboarding. */
export const applyReferralSchema = z.object({
  code: z
    .string()
    .trim()
    .min(4, 'code is required')
    .max(32, 'code is too long')
    .transform((s) => s.toUpperCase()),
});

export default { applyReferralSchema };
