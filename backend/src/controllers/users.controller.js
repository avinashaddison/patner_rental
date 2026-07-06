// Thin HTTP handlers for /users. See docs/API.md section 2.
import * as usersService from '../services/users.service.js';
import { ok, created } from '../utils/apiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';

// GET /users/me
export const getMe = asyncHandler(async (req, res) => {
  const user = await usersService.getMyProfile(req.user.id);
  return ok(res, { user });
});

// PATCH /users/me
export const updateMe = asyncHandler(async (req, res) => {
  const user = await usersService.updateMyProfile(req.user.id, req.body);
  return ok(res, { user });
});

// GET /users/:id  (public, limited)
export const getPublic = asyncHandler(async (req, res) => {
  const user = await usersService.getPublicProfile(req.user.id, req.params.id);
  return ok(res, { user });
});

// POST /users/block
export const block = asyncHandler(async (req, res) => {
  const result = await usersService.blockUser(req.user.id, req.body.blockedId);
  return created(res, result);
});

// DELETE /users/block/:blockedId
export const unblock = asyncHandler(async (req, res) => {
  const result = await usersService.unblockUser(req.user.id, req.params.blockedId);
  return ok(res, result);
});

// GET /users/blocks
export const blocks = asyncHandler(async (req, res) => {
  const list = await usersService.listBlocks(req.user.id);
  return ok(res, { blocks: list });
});

export default { getMe, updateMe, getPublic, block, unblock, blocks };
