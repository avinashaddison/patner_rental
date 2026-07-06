// Reviews routes — auto-mounted at /api/reviews.
import { Router } from 'express';
import { optionalAuth, requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as ctrl from '../controllers/reviews.controller.js';
import { createReviewBody, companionIdParam } from '../validators/reviews.validator.js';

const router = Router();

router.post('/', requireAuth, requireRole('CUSTOMER'), validate(createReviewBody), ctrl.create);
router.get('/companion/:companionId', optionalAuth, validate(companionIdParam, 'params'), ctrl.listForCompanion);

export default router;
