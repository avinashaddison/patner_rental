// Thin HTTP handlers for the companions module (req -> service -> res).
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import * as companionService from '../services/companions.service.js';

// ---- Public / discovery ----

export const search = asyncHandler(async (req, res) => {
  const { items, meta } = await companionService.searchCompanions(req.query, req.user);
  return ok(res, items, meta);
});

export const featured = asyncHandler(async (req, res) => {
  const { items, meta } = await companionService.listFeatured(req.query, req.user);
  return ok(res, items, meta);
});

export const popularNearby = asyncHandler(async (req, res) => {
  const lat = req.query.lat != null ? Number(req.query.lat) : undefined;
  const lng = req.query.lng != null ? Number(req.query.lng) : undefined;
  const city = req.query.city || undefined;
  const limit = req.query.limit;
  const items = await companionService.popularNearby({ lat, lng, city, limit }, req.user);
  return ok(res, items);
});

export const categories = asyncHandler(async (_req, res) => {
  const items = await companionService.listCategories();
  return ok(res, items);
});

export const detail = asyncHandler(async (req, res) => {
  const viewer = {
    lat: req.query.lat != null ? Number(req.query.lat) : undefined,
    lng: req.query.lng != null ? Number(req.query.lng) : undefined,
    userId: req.user?.id,
  };
  const profile = await companionService.getPublicProfile(req.params.id, viewer);
  return ok(res, profile);
});

export const availability = asyncHandler(async (req, res) => {
  const data = await companionService.getAvailableSlots(req.params.id, req.query.date);
  return ok(res, data);
});

export const reviews = asyncHandler(async (req, res) => {
  const { items, meta } = await companionService.listCompanionReviews(req.params.id, req.query);
  return ok(res, items, meta);
});

// ---- Companion-self ----

export const onboard = asyncHandler(async (req, res) => {
  const profile = await companionService.onboardCompanion(req.user, req.body);
  return created(res, profile);
});

export const myProfile = asyncHandler(async (req, res) => {
  const profile = await companionService.getOwnProfile(req.user);
  return ok(res, profile);
});

export const updateMe = asyncHandler(async (req, res) => {
  const profile = await companionService.updateOwnProfile(req.user, req.body);
  return ok(res, profile);
});

export const setOnline = asyncHandler(async (req, res) => {
  const data = await companionService.setOnline(req.user, req.body.isOnline);
  return ok(res, data);
});

export const addPhoto = asyncHandler(async (req, res) => {
  const photo = await companionService.addPhoto(req.user, req.body);
  return created(res, photo);
});

export const deletePhoto = asyncHandler(async (req, res) => {
  const data = await companionService.deletePhoto(req.user, req.params.photoId);
  return ok(res, data);
});

export const setAvailability = asyncHandler(async (req, res) => {
  const slots = await companionService.setAvailability(req.user, req.body.slots);
  return ok(res, slots);
});

export default {
  search,
  featured,
  popularNearby,
  categories,
  detail,
  availability,
  reviews,
  onboard,
  myProfile,
  updateMe,
  setOnline,
  addPhoto,
  deletePhoto,
  setAvailability,
};
