// Thin HTTP handlers for the social (posts/comments/likes/follows) module.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import * as posts from '../services/posts.service.js';

// ---- Posts ----

/** POST /posts — companion publishes a post. */
export const create = asyncHandler(async (req, res) => {
  const data = await posts.createPost(req.user, req.body);
  return created(res, data);
});

/** GET /posts/feed — following feed. */
export const feed = asyncHandler(async (req, res) => {
  const { items, meta } = await posts.listFeed(req.user, req.query);
  return ok(res, items, meta);
});

/** GET /posts — explore (or ?companionId= for a companion's grid). */
export const explore = asyncHandler(async (req, res) => {
  const { items, meta } = req.query.companionId
    ? await posts.listByCompanion(req.query.companionId, req.user, req.query)
    : await posts.listExplore(req.user, req.query);
  return ok(res, items, meta);
});

/** GET /posts/:id — single post. */
export const detail = asyncHandler(async (req, res) => {
  const data = await posts.getPost(req.params.id, req.user);
  return ok(res, data);
});

/** DELETE /posts/:id — owner companion deletes. */
export const remove = asyncHandler(async (req, res) => {
  const data = await posts.deletePost(req.params.id, req.user);
  return ok(res, data);
});

// ---- Likes ----

export const like = asyncHandler(async (req, res) => {
  const data = await posts.likePost(req.params.id, req.user);
  return ok(res, data);
});

export const unlike = asyncHandler(async (req, res) => {
  const data = await posts.unlikePost(req.params.id, req.user);
  return ok(res, data);
});

// ---- Comments ----

export const listComments = asyncHandler(async (req, res) => {
  const { items, meta } = await posts.listComments(req.params.id, req.user, req.query);
  return ok(res, items, meta);
});

export const addComment = asyncHandler(async (req, res) => {
  const data = await posts.addComment(req.params.id, req.user, req.body.body);
  return created(res, data);
});

export const deleteComment = asyncHandler(async (req, res) => {
  const data = await posts.deleteComment(req.params.commentId, req.user);
  return ok(res, data);
});

// ---- Follows (mounted under /companions/:id/follow) ----

export const follow = asyncHandler(async (req, res) => {
  const data = await posts.followCompanion(req.params.id, req.user);
  return ok(res, data);
});

export const unfollow = asyncHandler(async (req, res) => {
  const data = await posts.unfollowCompanion(req.params.id, req.user);
  return ok(res, data);
});

/** GET /companions/:id/posts — a companion's grid. */
export const companionPosts = asyncHandler(async (req, res) => {
  const { items, meta } = await posts.listByCompanion(req.params.id, req.user, req.query);
  return ok(res, items, meta);
});

export default {
  create,
  feed,
  explore,
  detail,
  remove,
  like,
  unlike,
  listComments,
  addComment,
  deleteComment,
  follow,
  unfollow,
  companionPosts,
};
