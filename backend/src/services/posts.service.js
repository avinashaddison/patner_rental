// Social module: Instagram-style companion photo posts + likes + comments + follows.
//
// - Companions (APPROVED) publish photo posts (1+ images + caption).
// - Customers follow companions, see a Following feed + an Explore discovery feed,
//   like + comment on posts, and use all of it to decide whom to book.
// - Block relationships are honoured across the feed/explore read paths (SAFETY.md).
// - Posts publish immediately as PUBLISHED; admins can flip them to REMOVED.
//
// Denormalized counters (Post.likeCount/commentCount, Companion.followerCount/postCount)
// are kept in sync inside the same $transaction as the row mutation, mirroring the
// reviews.service ratingAvg pattern.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { discoveryGenderFor } from '../utils/discovery.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import { notify } from './notification.service.js';

const MAX_IMAGES = 10;

// Shared include for post list/detail responses.
const postInclude = {
  companion: {
    select: {
      id: true,
      status: true,
      followerCount: true,
      user: { select: { id: true, fullName: true, profilePhotoUrl: true } },
      photos: {
        where: { isPrimary: true },
        select: { photoUrl: true },
        take: 1,
      },
    },
  },
};

/** Map a Post row (loaded with postInclude) to its API DTO. */
function postToDto(post, { likedSet = new Set(), followedSet = new Set(), viewerCompanionId = null } = {}) {
  const c = post.companion;
  const photoUrl = c?.photos?.[0]?.photoUrl || c?.user?.profilePhotoUrl || null;
  return {
    id: post.id,
    companionId: post.companionId,
    caption: post.caption || null,
    images: post.images || [],
    likeCount: post.likeCount,
    commentCount: post.commentCount,
    status: post.status,
    createdAt: post.createdAt,
    isLikedByMe: likedSet.has(post.id),
    isMine: viewerCompanionId != null && post.companionId === viewerCompanionId,
    author: c
      ? {
          companionId: c.id,
          userId: c.user?.id || null,
          name: c.user?.fullName || 'Companion',
          photoUrl,
          followerCount: c.followerCount ?? 0,
          isVerified: c.status === 'APPROVED',
          isFollowing: followedSet.has(post.companionId),
        }
      : null,
  };
}

/** Map a PostComment row (with user) to its API DTO. */
function commentToDto(c) {
  return {
    id: c.id,
    postId: c.postId,
    body: c.body,
    createdAt: c.createdAt,
    user: c.user
      ? { id: c.user.id, name: c.user.fullName || 'User', photoUrl: c.user.profilePhotoUrl || null }
      : null,
  };
}

/** UserIds with a block relationship (either direction) with `userId`. */
async function blockedUserIds(userId) {
  if (!userId) return [];
  const blocks = await prisma.block.findMany({
    where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
    select: { blockerId: true, blockedId: true },
  });
  const set = new Set();
  for (const b of blocks) {
    set.add(b.blockerId);
    set.add(b.blockedId);
  }
  set.delete(userId);
  return [...set];
}

/** Which of `postIds` the given user has liked. */
async function likedPostIds(userId, postIds) {
  if (!userId || postIds.length === 0) return new Set();
  const likes = await prisma.postLike.findMany({
    where: { userId, postId: { in: postIds } },
    select: { postId: true },
  });
  return new Set(likes.map((l) => l.postId));
}

/** True if a block relationship exists in EITHER direction between two users. */
async function isBlockedWith(userId, otherUserId) {
  if (!userId || !otherUserId || userId === otherUserId) return false;
  const block = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: userId, blockedId: otherUserId },
        { blockerId: otherUserId, blockedId: userId },
      ],
    },
    select: { id: true },
  });
  return Boolean(block);
}

/** Which of `companionIds` the given user follows. */
async function followedCompanionIds(userId, companionIds) {
  if (!userId || companionIds.length === 0) return new Set();
  const follows = await prisma.follow.findMany({
    where: { followerId: userId, companionId: { in: companionIds } },
    select: { companionId: true },
  });
  return new Set(follows.map((f) => f.companionId));
}

/** Run a paginated post query and shape it for the API. */
async function listPostsWhere(where, user, query) {
  const { skip, take, page, limit } = getPagination({ query });
  const [rows, total] = await Promise.all([
    prisma.post.findMany({ where, include: postInclude, orderBy: { createdAt: 'desc' }, skip, take }),
    prisma.post.count({ where }),
  ]);
  const [likedSet, followedSet] = await Promise.all([
    likedPostIds(user?.id, rows.map((r) => r.id)),
    followedCompanionIds(user?.id, rows.map((r) => r.companionId)),
  ]);
  return {
    items: rows.map((r) => postToDto(r, { likedSet, followedSet, viewerCompanionId: user?.companion?.id })),
    meta: buildMeta(total, page, limit),
  };
}

// ---- Create / read / delete -------------------------------------------------

/** COMPANION (APPROVED) publishes a post. */
export async function createPost(user, { caption, images }) {
  if (!user.companion) throw ApiError.forbidden('Only companions can publish posts');
  if (user.companion.status !== 'APPROVED') {
    throw ApiError.forbidden('Your companion profile must be approved before you can post');
  }
  if (!Array.isArray(images) || images.length === 0) {
    throw ApiError.badRequest('At least one image is required');
  }
  if (images.length > MAX_IMAGES) {
    throw ApiError.badRequest(`A post can have at most ${MAX_IMAGES} images`);
  }

  const post = await prisma.$transaction(async (tx) => {
    const created = await tx.post.create({
      data: { companionId: user.companion.id, caption: caption?.trim() || null, images },
    });
    await tx.companion.update({
      where: { id: user.companion.id },
      data: { postCount: { increment: 1 } },
    });
    return created;
  });

  return getPost(post.id, user);
}

/** Following feed — posts from companions the user follows. */
export async function listFeed(user, query) {
  const [follows, blocked] = await Promise.all([
    prisma.follow.findMany({ where: { followerId: user.id }, select: { companionId: true } }),
    blockedUserIds(user.id),
  ]);
  const companionIds = follows.map((f) => f.companionId);
  const where = {
    status: 'PUBLISHED',
    companionId: { in: companionIds },
    companion: { user: { id: { notIn: blocked } } },
  };
  return listPostsWhere(where, user, query);
}

/** Explore — all published posts from approved companions (block-aware). */
export async function listExplore(user, query) {
  const blocked = await blockedUserIds(user?.id);
  // Discovery surface — apply opposite-gender matching (see utils/discovery.js).
  const gender = discoveryGenderFor(user);
  const where = {
    status: 'PUBLISHED',
    companion: {
      status: 'APPROVED',
      user: { id: { notIn: blocked }, ...(gender ? { gender } : {}) },
    },
  };
  return listPostsWhere(where, user, query);
}

/** A single companion's published posts (their profile grid). Block-aware. */
export async function listByCompanion(companionId, user, query) {
  const blocked = await blockedUserIds(user?.id);
  const where = {
    companionId,
    status: 'PUBLISHED',
    companion: { status: 'APPROVED', user: { id: { notIn: blocked } } },
  };
  return listPostsWhere(where, user, query);
}

/** Single post detail. */
export async function getPost(postId, user) {
  const post = await prisma.post.findUnique({ where: { id: postId }, include: postInclude });
  if (!post) throw ApiError.notFound('Post not found');
  const isOwner = user?.companion && post.companionId === user.companion.id;
  if (post.status !== 'PUBLISHED' && !isOwner) throw ApiError.notFound('Post not found');
  // Honour block relationships on the read path (SAFETY.md).
  if (!isOwner && (await isBlockedWith(user?.id, post.companion?.user?.id))) {
    throw ApiError.notFound('Post not found');
  }
  const [likedSet, followedSet] = await Promise.all([
    likedPostIds(user?.id, [post.id]),
    followedCompanionIds(user?.id, [post.companionId]),
  ]);
  return postToDto(post, { likedSet, followedSet, viewerCompanionId: user?.companion?.id });
}

/** Owner companion deletes their post. */
export async function deletePost(postId, user) {
  const post = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true, companionId: true, status: true },
  });
  if (!post) throw ApiError.notFound('Post not found');
  if (!user.companion || post.companionId !== user.companion.id) {
    throw ApiError.forbidden('You can only delete your own posts');
  }
  await prisma.$transaction(async (tx) => {
    await tx.post.delete({ where: { id: postId } });
    // postCount tracks PUBLISHED posts. An admin-REMOVED post already had its
    // count decremented at removal time, so only decrement here when it was
    // still PUBLISHED — prevents a double-decrement (and negative counts).
    if (post.status === 'PUBLISHED') {
      await tx.companion.update({
        where: { id: post.companionId },
        data: { postCount: { decrement: 1 } },
      });
    }
  });
  return { id: postId, deleted: true };
}

// ---- Likes ------------------------------------------------------------------

export async function likePost(postId, user) {
  const post = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true, status: true, companion: { select: { userId: true } } },
  });
  if (!post || post.status !== 'PUBLISHED') throw ApiError.notFound('Post not found');
  if (await isBlockedWith(user.id, post.companion.userId)) {
    throw ApiError.notFound('Post not found');
  }

  try {
    await prisma.$transaction(async (tx) => {
      await tx.postLike.create({ data: { postId, userId: user.id } });
      await tx.post.update({ where: { id: postId }, data: { likeCount: { increment: 1 } } });
    });
    if (post.companion.userId !== user.id) {
      notify(post.companion.userId, {
        type: 'SYSTEM',
        title: 'New like',
        body: `${user.fullName || 'Someone'} liked your post.`,
        data: { kind: 'POST_LIKE', postId },
      }).catch(() => {});
    }
  } catch (err) {
    if (err?.code !== 'P2002') throw err; // already liked → idempotent
  }

  const fresh = await prisma.post.findUnique({ where: { id: postId }, select: { likeCount: true } });
  return { liked: true, likeCount: fresh?.likeCount ?? 0 };
}

export async function unlikePost(postId, user) {
  const existing = await prisma.postLike.findUnique({
    where: { postId_userId: { postId, userId: user.id } },
    select: { id: true },
  });
  if (existing) {
    await prisma.$transaction(async (tx) => {
      await tx.postLike.delete({ where: { id: existing.id } });
      await tx.post.update({ where: { id: postId }, data: { likeCount: { decrement: 1 } } });
    });
  }
  const fresh = await prisma.post.findUnique({ where: { id: postId }, select: { likeCount: true } });
  return { liked: false, likeCount: fresh?.likeCount ?? 0 };
}

// ---- Comments ---------------------------------------------------------------

export async function listComments(postId, user, query) {
  const post = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true, status: true, companionId: true, companion: { select: { userId: true } } },
  });
  if (!post) throw ApiError.notFound('Post not found');
  const isOwner = user?.companion && post.companionId === user.companion.id;
  // A removed post (and its thread) is hidden from non-owners; honour blocks too.
  if (!isOwner) {
    if (post.status !== 'PUBLISHED') throw ApiError.notFound('Post not found');
    if (await isBlockedWith(user?.id, post.companion?.userId)) {
      throw ApiError.notFound('Post not found');
    }
  }
  const blocked = await blockedUserIds(user?.id);
  const { skip, take, page, limit } = getPagination({ query });
  const where = { postId, userId: { notIn: blocked } };
  const [rows, total] = await Promise.all([
    prisma.postComment.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      include: { user: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
    }),
    prisma.postComment.count({ where }),
  ]);
  return { items: rows.map(commentToDto), meta: buildMeta(total, page, limit) };
}

export async function addComment(postId, user, body) {
  const post = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true, status: true, companion: { select: { userId: true } } },
  });
  if (!post || post.status !== 'PUBLISHED') throw ApiError.notFound('Post not found');
  if (await isBlockedWith(user.id, post.companion.userId)) {
    throw ApiError.notFound('Post not found');
  }

  const comment = await prisma.$transaction(async (tx) => {
    const created = await tx.postComment.create({
      data: { postId, userId: user.id, body: body.trim() },
      include: { user: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
    });
    await tx.post.update({ where: { id: postId }, data: { commentCount: { increment: 1 } } });
    return created;
  });

  if (post.companion.userId !== user.id) {
    notify(post.companion.userId, {
      type: 'SYSTEM',
      title: 'New comment',
      body: `${user.fullName || 'Someone'} commented on your post.`,
      data: { kind: 'POST_COMMENT', postId },
    }).catch(() => {});
  }

  return commentToDto(comment);
}

export async function deleteComment(commentId, user) {
  const comment = await prisma.postComment.findUnique({
    where: { id: commentId },
    select: { id: true, postId: true, userId: true, post: { select: { companionId: true } } },
  });
  if (!comment) throw ApiError.notFound('Comment not found');
  const isAuthor = comment.userId === user.id;
  const isPostOwner = user.companion && comment.post.companionId === user.companion.id;
  if (!isAuthor && !isPostOwner) {
    throw ApiError.forbidden('You cannot delete this comment');
  }
  await prisma.$transaction(async (tx) => {
    await tx.postComment.delete({ where: { id: commentId } });
    await tx.post.update({
      where: { id: comment.postId },
      data: { commentCount: { decrement: 1 } },
    });
  });
  return { id: commentId, deleted: true };
}

// ---- Follows ----------------------------------------------------------------

export async function followCompanion(companionId, user) {
  const companion = await prisma.companion.findUnique({
    where: { id: companionId },
    select: { id: true, userId: true, status: true },
  });
  if (!companion || companion.status !== 'APPROVED') throw ApiError.notFound('Companion not found');
  if (companion.userId === user.id) throw ApiError.badRequest('You cannot follow yourself');
  if (await isBlockedWith(user.id, companion.userId)) {
    throw ApiError.notFound('Companion not found');
  }

  try {
    await prisma.$transaction(async (tx) => {
      await tx.follow.create({ data: { followerId: user.id, companionId } });
      await tx.companion.update({
        where: { id: companionId },
        data: { followerCount: { increment: 1 } },
      });
    });
    notify(companion.userId, {
      type: 'SYSTEM',
      title: 'New follower',
      body: `${user.fullName || 'Someone'} started following you.`,
      data: { kind: 'FOLLOW', companionId },
    }).catch(() => {});
  } catch (err) {
    if (err?.code !== 'P2002') throw err; // already following → idempotent
  }

  const fresh = await prisma.companion.findUnique({
    where: { id: companionId },
    select: { followerCount: true },
  });
  return { following: true, followerCount: fresh?.followerCount ?? 0 };
}

export async function unfollowCompanion(companionId, user) {
  const existing = await prisma.follow.findUnique({
    where: { followerId_companionId: { followerId: user.id, companionId } },
    select: { id: true },
  });
  if (existing) {
    await prisma.$transaction(async (tx) => {
      await tx.follow.delete({ where: { id: existing.id } });
      await tx.companion.update({
        where: { id: companionId },
        data: { followerCount: { decrement: 1 } },
      });
    });
  }
  const fresh = await prisma.companion.findUnique({
    where: { id: companionId },
    select: { followerCount: true },
  });
  return { following: false, followerCount: fresh?.followerCount ?? 0 };
}

export default {
  createPost,
  listFeed,
  listExplore,
  listByCompanion,
  getPost,
  deletePost,
  likePost,
  unlikePost,
  listComments,
  addComment,
  deleteComment,
  followCompanion,
  unfollowCompanion,
};
