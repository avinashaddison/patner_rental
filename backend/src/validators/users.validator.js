// Zod request schemas for the users/profile module (docs/API.md section 2).
import { z } from 'zod';

export const updateMeSchema = z
  .object({
    fullName: z.string().trim().min(2, 'Full name is too short').max(80).optional(),
    city: z.string().trim().min(2).max(60).optional(),
    email: z.string().trim().toLowerCase().email('Enter a valid email').optional(),
    profilePhotoUrl: z.string().trim().url('profilePhotoUrl must be a valid URL').optional(),
  })
  .refine((v) => Object.keys(v).length > 0, {
    message: 'Provide at least one field to update',
  });

export const blockSchema = z.object({
  blockedId: z.string({ required_error: 'blockedId is required' }).trim().uuid('blockedId must be a valid id'),
});

export const userIdParamSchema = z.object({
  id: z.string().trim().uuid('Invalid user id'),
});

export const blockedIdParamSchema = z.object({
  blockedId: z.string().trim().uuid('Invalid user id'),
});

export default { updateMeSchema, blockSchema, userIdParamSchema, blockedIdParamSchema };
