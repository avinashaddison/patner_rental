// Social posts routes — auto-mounted at /api/posts.
// Companions publish photo posts; everyone (authed) can browse the feed/explore,
// like, and comment. Static paths are declared BEFORE the dynamic /:id route.
import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { apiLimiter } from '../middleware/rateLimit.js';
import {
  createPostSchema,
  listQuerySchema,
  postIdParamSchema,
  commentIdParamSchema,
  addCommentSchema,
} from '../validators/posts.validator.js';
import * as ctrl from '../controllers/posts.controller.js';

const router = Router();

// Every social endpoint requires an authenticated user.
router.use(requireAuth);

// --- Create (companion only) ---
router.post('/', requireRole('COMPANION'), apiLimiter, validate(createPostSchema), ctrl.create);

// --- Lists (static before dynamic) ---
router.get('/feed', validate(listQuerySchema, 'query'), ctrl.feed);
router.get('/', validate(listQuerySchema, 'query'), ctrl.explore);

// --- Comment delete (two-segment path; declared before single-segment /:id) ---
router.delete('/comments/:commentId', validate(commentIdParamSchema, 'params'), ctrl.deleteComment);

// --- Single post ---
router.get('/:id', validate(postIdParamSchema, 'params'), ctrl.detail);
router.delete('/:id', validate(postIdParamSchema, 'params'), ctrl.remove);

// --- Likes ---
router.post('/:id/like', validate(postIdParamSchema, 'params'), ctrl.like);
router.delete('/:id/like', validate(postIdParamSchema, 'params'), ctrl.unlike);

// --- Comments ---
router.get('/:id/comments', validate(postIdParamSchema, 'params'), validate(listQuerySchema, 'query'), ctrl.listComments);
router.post('/:id/comments', validate(postIdParamSchema, 'params'), validate(addCommentSchema), ctrl.addComment);

export default router;
