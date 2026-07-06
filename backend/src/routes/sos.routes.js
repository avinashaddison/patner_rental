// SOS routes — auto-mounted at /api/sos.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { createSosSchema, sosIdParam } from '../validators/sos.validator.js';
import * as sos from '../controllers/sos.controller.js';

const router = Router();

router.use(requireAuth);

router.post('/', validate(createSosSchema), sos.create);
router.get('/active', sos.listActive);
router.post('/:id/cancel', validate(sosIdParam, 'params'), sos.cancel);

export default router;
