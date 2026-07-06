// Wallet + payouts routes — auto-mounted at /api/wallet.
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { createPayoutSchema } from '../validators/wallet.validator.js';
import {
  getWallet,
  getTransactions,
  postPayout,
  getPayouts,
} from '../controllers/wallet.controller.js';

const router = Router();

// Any authenticated user has a wallet (companions earn; customers hold credit).
router.get('/', requireAuth, asyncHandler(getWallet));
router.get('/transactions', requireAuth, asyncHandler(getTransactions));

// Payouts are companion-only.
router.post(
  '/payouts',
  requireAuth,
  requireRole('COMPANION'),
  validate(createPayoutSchema),
  asyncHandler(postPayout),
);
router.get('/payouts', requireAuth, requireRole('COMPANION'), asyncHandler(getPayouts));

export default router;
