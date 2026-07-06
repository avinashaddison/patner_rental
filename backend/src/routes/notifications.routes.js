// Notifications routes — auto-mounted at /api/notifications.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { notificationIdParam } from '../validators/notifications.validator.js';
import * as notifications from '../controllers/notifications.controller.js';

const router = Router();

router.use(requireAuth);

router.get('/', notifications.list);
router.get('/unread-count', notifications.unreadCount);
router.post('/read-all', notifications.markAllRead);
router.post('/:id/read', validate(notificationIdParam, 'params'), notifications.markRead);

export default router;
