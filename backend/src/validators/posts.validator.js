// Zod request schemas for the social (posts/comments/follows) module.
import { z } from 'zod';

const uuid = z.string().uuid('Invalid id');

// Image URLs are already-uploaded R2 public URLs (presign flow), like companion photos.
const imageUrl = z.string().url('Each image must be a valid URL').max(1000);

/** POST /posts */
export const createPostSchema = z.object({
  caption: z.string().trim().max(2000).optional(),
  images: z.array(imageUrl).min(1, 'At least one image is required').max(10),
});

/** GET /posts, /posts/feed, /companions/:id/posts, /posts/:id/comments */
export const listQuerySchema = z.object({
  companionId: uuid.optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
  sort: z.string().optional(),
});

/** Route param carrying a post id. */
export const postIdParamSchema = z.object({ id: uuid });

/** Route param carrying a comment id. */
export const commentIdParamSchema = z.object({ commentId: uuid });

/** Route param carrying a companion id. */
export const companionIdParamSchema = z.object({ id: uuid });

/** POST /posts/:id/comments */
export const addCommentSchema = z.object({
  body: z.string().trim().min(1, 'Comment cannot be empty').max(1000),
});

export default {
  createPostSchema,
  listQuerySchema,
  postIdParamSchema,
  commentIdParamSchema,
  companionIdParamSchema,
  addCommentSchema,
};
