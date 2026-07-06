// Reports routes — auto-mounted at /api/reports.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { createReportSchema } from '../validators/reports.validator.js';
import * as reports from '../controllers/reports.controller.js';

const router = Router();

router.use(requireAuth);

router.post('/', validate(createReportSchema), reports.create);
router.get('/mine', reports.listMine);

export default router;
