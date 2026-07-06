// Users / profile routes — auto-mounted at /api/users. See docs/API.md section 2.
import { Router } from 'express';
import * as usersController from '../controllers/users.controller.js';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import {
  updateMeSchema,
  blockSchema,
  userIdParamSchema,
  blockedIdParamSchema,
} from '../validators/users.validator.js';

const router = Router();

// All user routes require authentication.
router.use(requireAuth);

// Self profile.
router.get('/me', usersController.getMe);
router.patch('/me', validate(updateMeSchema), usersController.updateMe);

// Blocks — declared BEFORE "/:id" so these static paths are not captured by the param route.
router.get('/blocks', usersController.blocks);
router.post('/block', validate(blockSchema), usersController.block);
router.delete('/block/:blockedId', validate(blockedIdParamSchema, 'params'), usersController.unblock);

// Public (limited) profile of another user.
router.get('/:id', validate(userIdParamSchema, 'params'), usersController.getPublic);

export default router;
