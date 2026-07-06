// Uploads routes — auto-mounted at /api/uploads.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { presignSchema } from '../validators/uploads.validator.js';
import * as uploads from '../controllers/uploads.controller.js';

const router = Router();

router.use(requireAuth);

router.post('/presign', validate(presignSchema), uploads.presign);

export default router;
