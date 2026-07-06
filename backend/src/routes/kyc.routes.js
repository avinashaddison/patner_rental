// KYC routes — auto-mounted at /api/kyc. Companion-only.
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as ctrl from '../controllers/kyc.controller.js';
import { submitKycBody } from '../validators/kyc.validator.js';

const router = Router();

router.post('/submit', requireAuth, requireRole('COMPANION'), validate(submitKycBody), ctrl.submit);
router.get('/status', requireAuth, requireRole('COMPANION'), ctrl.status);

export default router;
