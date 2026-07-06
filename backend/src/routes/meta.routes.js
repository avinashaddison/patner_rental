// Meta routes — auto-mounted at /api/meta. Public (no auth).
import { Router } from 'express';
import * as meta from '../controllers/meta.controller.js';

const router = Router();

router.get('/config', meta.getConfig);
router.get('/health', meta.health);

export default router;
