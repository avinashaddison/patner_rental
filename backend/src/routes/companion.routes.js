// Companion dashboard routes. Auto-mounted at /api/companion by routes/index.js.
// Distinct from /api/companions (public companion profiles/search). All endpoints
// here are restricted to authenticated users with the COMPANION role.
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { listBookingsQuerySchema } from '../validators/bookings.validator.js';
import { updateLocationSchema } from '../validators/companion.validator.js';
import * as ctrl from '../controllers/companion.controller.js';

const router = Router();

router.use(requireAuth, requireRole('COMPANION'));

router.get('/dashboard', ctrl.dashboard);
router.get('/earnings', ctrl.earnings);
router.get('/bookings', validate(listBookingsQuerySchema, 'query'), ctrl.bookings);
router.patch('/location', validate(updateLocationSchema), ctrl.updateLocation);

export default router;
