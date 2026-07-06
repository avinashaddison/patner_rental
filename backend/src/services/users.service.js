// Users / profile business logic: self profile read/update, public profile,
// and the block system. The block helpers are the shared enforcement point used
// by chat + booking to prevent interaction between blocked parties.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { computeAge, publicUser } from './auth.service.js';

/** Full self profile (with companion). */
export async function getMyProfile(userId) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { companion: true },
  });
  if (!user) throw ApiError.notFound('User not found');
  return publicUser(user);
}

/** Patch self profile. Only the whitelisted fields from the validator reach here. */
export async function updateMyProfile(userId, input) {
  const data = {};
  if (input.fullName !== undefined) data.fullName = input.fullName;
  if (input.city !== undefined) data.city = input.city;
  if (input.profilePhotoUrl !== undefined) data.profilePhotoUrl = input.profilePhotoUrl;

  if (input.email !== undefined) {
    const taken = await prisma.user.findFirst({
      where: { email: input.email, NOT: { id: userId } },
      select: { id: true },
    });
    if (taken) throw ApiError.conflict('This email is already in use.');
    data.email = input.email;
  }

  const user = await prisma.user.update({
    where: { id: userId },
    data,
    include: { companion: true },
  });
  return publicUser(user);
}

/**
 * Public, limited view of another user. Respects blocks in BOTH directions
 * (a blocked relationship hides the profile from each other).
 */
export async function getPublicProfile(viewerId, targetId) {
  const user = await prisma.user.findUnique({
    where: { id: targetId },
    include: { companion: true },
  });
  if (!user || user.isBlocked) throw ApiError.notFound('User not found');

  if (viewerId && (await isBlockedEitherWay(viewerId, targetId))) {
    throw ApiError.notFound('User not found');
  }

  return {
    id: user.id,
    fullName: user.fullName,
    username: user.username,
    city: user.city,
    profilePhotoUrl: user.profilePhotoUrl,
    role: user.role,
    age: user.dateOfBirth ? computeAge(user.dateOfBirth) : null,
    isCompanion: user.role === 'COMPANION',
    companion: user.companion
      ? {
          id: user.companion.id,
          status: user.companion.status,
          city: user.companion.city,
          ratingAvg: user.companion.ratingAvg,
          ratingCount: user.companion.ratingCount,
          isOnline: user.companion.isOnline,
          isFeatured: user.companion.isFeatured,
        }
      : undefined,
    createdAt: user.createdAt,
  };
}

/** Block another user. Idempotent (re-blocking is a no-op). */
export async function blockUser(blockerId, blockedId) {
  if (blockerId === blockedId) {
    throw ApiError.badRequest('You cannot block yourself.');
  }

  const target = await prisma.user.findUnique({
    where: { id: blockedId },
    select: { id: true },
  });
  if (!target) throw ApiError.notFound('User to block not found');

  const block = await prisma.block.upsert({
    where: { blockerId_blockedId: { blockerId, blockedId } },
    create: { blockerId, blockedId },
    update: {},
  });

  return { id: block.id, blockedId, blocked: true };
}

/** Unblock a previously blocked user. Idempotent. */
export async function unblockUser(blockerId, blockedId) {
  await prisma.block.deleteMany({ where: { blockerId, blockedId } });
  return { blockedId, blocked: false };
}

/** List users the caller has blocked, with a light profile of each. */
export async function listBlocks(blockerId) {
  const blocks = await prisma.block.findMany({
    where: { blockerId },
    orderBy: { createdAt: 'desc' },
    include: {
      blocked: {
        select: { id: true, fullName: true, profilePhotoUrl: true, city: true, role: true },
      },
    },
  });

  return blocks.map((b) => ({
    id: b.id,
    blockedId: b.blockedId,
    createdAt: b.createdAt,
    user: b.blocked,
  }));
}

/**
 * Has `blockerId` blocked `blockedId`? (directional)
 * Shared helper for booking/chat enforcement.
 */
export async function hasBlocked(blockerId, blockedId) {
  if (!blockerId || !blockedId) return false;
  const row = await prisma.block.findUnique({
    where: { blockerId_blockedId: { blockerId, blockedId } },
    select: { id: true },
  });
  return Boolean(row);
}

/**
 * Is there a block between two users in EITHER direction?
 * Use this to gate chat + booking — if either party blocked the other, deny.
 */
export async function isBlockedEitherWay(userA, userB) {
  if (!userA || !userB || userA === userB) return false;
  const row = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: userA, blockedId: userB },
        { blockerId: userB, blockedId: userA },
      ],
    },
    select: { id: true },
  });
  return Boolean(row);
}

/**
 * Guard helper for callers: throws FORBIDDEN if either party has blocked the other.
 * Booking/chat modules call this before allowing an interaction.
 */
export async function assertNotBlocked(userA, userB, message = 'Interaction not allowed between these users.') {
  if (await isBlockedEitherWay(userA, userB)) {
    throw ApiError.forbidden(message);
  }
}

export default {
  getMyProfile,
  updateMyProfile,
  getPublicProfile,
  blockUser,
  unblockUser,
  listBlocks,
  hasBlocked,
  isBlockedEitherWay,
  assertNotBlocked,
};
