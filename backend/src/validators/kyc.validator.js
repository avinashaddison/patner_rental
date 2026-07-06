// Zod request schemas for the KYC module.
import { z } from 'zod';

/** POST /kyc/submit */
export const submitKycBody = z.object({
  documentType: z.enum(['GOVERNMENT_ID', 'SELFIE']),
  documentUrl: z.string().url().max(1000),
  documentNumber: z.string().trim().min(1).max(60).optional(),
});

export default { submitKycBody };
