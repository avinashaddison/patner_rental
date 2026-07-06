// Referrals routes — auto-mounted at /api/referrals.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { applyReferralSchema } from '../validators/referrals.validator.js';
import { getMine, postApply } from '../controllers/referrals.controller.js';

const router = Router();

router.get('/me', requireAuth, asyncHandler(getMine));
router.post('/apply', requireAuth, validate(applyReferralSchema), asyncHandler(postApply));

export default router;
