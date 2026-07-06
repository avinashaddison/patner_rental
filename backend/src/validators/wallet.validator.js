// Zod request schemas for the wallet + payouts domain.
import { z } from 'zod';

/**
 * POST /wallet/payouts — request a withdrawal.
 * UPI requires upiId; BANK_TRANSFER requires bankAccountName + bankAccountNumber + ifsc.
 * Amount is validated against min_payout / available balance in the service.
 */
export const createPayoutSchema = z
  .object({
    amount: z.coerce
      .number({ invalid_type_error: 'amount must be a number' })
      .positive('amount must be greater than 0'),
    method: z.enum(['UPI', 'BANK_TRANSFER'], {
      errorMap: () => ({ message: 'method must be UPI or BANK_TRANSFER' }),
    }),
    upiId: z.string().trim().min(3).max(120).optional(),
    bankAccountName: z.string().trim().min(2).max(120).optional(),
    bankAccountNumber: z.string().trim().min(6).max(34).optional(),
    ifsc: z
      .string()
      .trim()
      .regex(/^[A-Za-z]{4}0[A-Za-z0-9]{6}$/, 'ifsc must be a valid IFSC code')
      .optional(),
  })
  .superRefine((data, ctx) => {
    if (data.method === 'UPI') {
      if (!data.upiId) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['upiId'],
          message: 'upiId is required for UPI payouts',
        });
      }
    } else if (data.method === 'BANK_TRANSFER') {
      if (!data.bankAccountName) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['bankAccountName'],
          message: 'bankAccountName is required for bank transfers',
        });
      }
      if (!data.bankAccountNumber) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['bankAccountNumber'],
          message: 'bankAccountNumber is required for bank transfers',
        });
      }
      if (!data.ifsc) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['ifsc'],
          message: 'ifsc is required for bank transfers',
        });
      }
    }
  });

export default { createPayoutSchema };
