// Companions routes — auto-mounted at /api/companions.
// IMPORTANT: static + /me routes are declared BEFORE the dynamic /:id route so
// they are not shadowed by the wildcard.
import { Router } from 'express';
import { optionalAuth, requireAuth, requireRole } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import * as ctrl from '../controllers/companions.controller.js';
import * as postsCtrl from '../controllers/posts.controller.js';
import {
  searchCompanionsQuery,
  nearbyQuery,
  availabilityQuery,
  onboardCompanionBody,
  updateCompanionBody,
  onlineBody,
  addPhotoBody,
  setAvailabilityBody,
} from '../validators/companions.validator.js';
import { listQuerySchema, companionIdParamSchema } from '../validators/posts.validator.js';

const router = Router();

// ---- Companion-self (role=COMPANION) ----
// Onboarding also accepts CUSTOMER: "Become a Companion" upgrades the role to
// COMPANION when the profile is created (approval still gated by admin/KYC).
router.post('/me', requireAuth, requireRole('COMPANION', 'CUSTOMER'), validate(onboardCompanionBody), ctrl.onboard);
router.get('/me/profile', requireAuth, requireRole('COMPANION'), ctrl.myProfile);
router.patch('/me', requireAuth, requireRole('COMPANION'), validate(updateCompanionBody), ctrl.updateMe);
router.patch('/me/online', requireAuth, requireRole('COMPANION'), validate(onlineBody), ctrl.setOnline);
router.post('/me/photos', requireAuth, requireRole('COMPANION'), validate(addPhotoBody), ctrl.addPhoto);
router.delete('/me/photos/:photoId', requireAuth, requireRole('COMPANION'), ctrl.deletePhoto);
router.put('/me/availability', requireAuth, requireRole('COMPANION'), validate(setAvailabilityBody), ctrl.setAvailability);

// ---- Public / discovery (static paths before /:id) ----
router.get('/featured', optionalAuth, ctrl.featured);
router.get('/popular-nearby', optionalAuth, validate(nearbyQuery, 'query'), ctrl.popularNearby);
router.get('/categories', ctrl.categories);
router.get('/', optionalAuth, validate(searchCompanionsQuery, 'query'), ctrl.search);

// ---- Dynamic by id ----
router.get('/:id', optionalAuth, ctrl.detail);
router.get('/:id/availability', optionalAuth, validate(availabilityQuery, 'query'), ctrl.availability);
router.get('/:id/reviews', optionalAuth, ctrl.reviews);

// ---- Social: posts grid + follow toggle ----
router.get(
  '/:id/posts',
  optionalAuth,
  validate(companionIdParamSchema, 'params'),
  validate(listQuerySchema, 'query'),
  postsCtrl.companionPosts,
);
router.post('/:id/follow', requireAuth, validate(companionIdParamSchema, 'params'), postsCtrl.follow);
router.delete('/:id/follow', requireAuth, validate(companionIdParamSchema, 'params'), postsCtrl.unfollow);

export default router;
