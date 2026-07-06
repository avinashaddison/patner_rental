// Live-tracking routes — auto-mounted at /api/tracking.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import {
  routeSchema,
  autocompleteSchema,
  placeDetailsSchema,
  reverseGeocodeSchema,
} from '../validators/tracking.validator.js';
import * as tracking from '../controllers/tracking.controller.js';

const router = Router();

router.use(requireAuth);

router.post('/route', validate(routeSchema), tracking.route);
router.get(
  '/places/autocomplete',
  validate(autocompleteSchema, 'query'),
  tracking.placesAutocomplete,
);
router.get(
  '/places/details',
  validate(placeDetailsSchema, 'query'),
  tracking.placeDetails,
);
router.get(
  '/geocode/reverse',
  validate(reverseGeocodeSchema, 'query'),
  tracking.reverseGeocode,
);

export default router;
