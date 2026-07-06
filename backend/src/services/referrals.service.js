// Referrals business logic.
// Each user owns a unique referralCode (generated at signup). Applying a code links the
// applicant as the referrer's referee and creates a PENDING Referral row. The reward
// (₹100 default) is credited to the REFERRER on the referee's first COMPLETED booking —
// that crediting lives in ledger.service.applyReferralRewardIfEligible (called by the
// bookings/complete flow), keeping money movement in one place.
import pkg from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';
import { getReferralReward } from './settings.service.js';
import { notify } from './notification.service.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

/**
 * GET /referrals/me — the user's code, totals, and list of people they referred.
 * totalEarned sums COMPLETED (rewarded) referrals' rewardAmount.
 */
export async function getMyReferrals(userId) {
  const me = await prisma.user.findUnique({
    where: { id: userId },
    select: { referralCode: true },
  });
  if (!me) throw ApiError.notFound('User not found');

  const referrals = await prisma.referral.findMany({
    where: { referrerId: userId },
    orderBy: { createdAt: 'desc' },
    include: {
      referred: {
        select: { id: true, fullName: true, profilePhotoUrl: true, createdAt: true },
      },
    },
  });

  let totalEarned = D(0);
  const list = referrals.map((r) => {
    if (r.rewarded) totalEarned = totalEarned.plus(D(r.rewardAmount));
    return {
      id: r.id,
      status: r.status,
      rewardAmount: Number(D(r.rewardAmount)),
      rewarded: r.rewarded,
      rewardedAt: r.rewardedAt,
      createdAt: r.createdAt,
      referredUser: r.referred
        ? {
            id: r.referred.id,
            name: r.referred.fullName,
            photoUrl: r.referred.profilePhotoUrl,
            joinedAt: r.referred.createdAt,
          }
        : null,
    };
  });

  const reward = await getReferralReward();

  return {
    referralCode: me.referralCode,
    rewardPerReferral: Number(reward),
    totalReferred: referrals.length,
    totalCompleted: referrals.filter((r) => r.status === 'COMPLETED').length,
    totalEarned: Number(totalEarned.toDecimalPlaces(2)),
    referrals: list,
  };
}

/**
 * POST /referrals/apply — apply a referrer's code (during onboarding).
 * Rules: code must exist; cannot self-refer; user must not already be referred.
 * Creates a PENDING Referral and sets user.referredById. The reward is paid later, on
 * the referee's first COMPLETED booking.
 */
export async function applyReferralCode(userId, code) {
  const applicant = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, referredById: true, referralCode: true, fullName: true },
  });
  if (!applicant) throw ApiError.notFound('User not found');

  if (applicant.referralCode === code) {
    throw ApiError.badRequest('You cannot use your own referral code');
  }
  if (applicant.referredById) {
    throw ApiError.conflict('A referral code has already been applied to your account');
  }

  const existingReferral = await prisma.referral.findUnique({ where: { referredId: userId } });
  if (existingReferral) {
    throw ApiError.conflict('A referral code has already been applied to your account');
  }

  const referrer = await prisma.user.findUnique({
    where: { referralCode: code },
    select: { id: true, fullName: true },
  });
  if (!referrer) throw ApiError.notFound('Invalid referral code');
  if (referrer.id === userId) {
    throw ApiError.badRequest('You cannot use your own referral code');
  }

  const rewardAmount = await getReferralReward();

  let referral;
  try {
    referral = await prisma.$transaction(async (tx) => {
      const created = await tx.referral.create({
        data: {
          referrerId: referrer.id,
          referredId: userId,
          status: 'PENDING',
          rewardAmount: D(rewardAmount).toDecimalPlaces(2),
          rewarded: false,
        },
      });
      await tx.user.update({
        where: { id: userId },
        data: { referredById: referrer.id },
      });
      return created;
    });
  } catch (err) {
    // Unique constraint race (referredId already set concurrently).
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      throw ApiError.conflict('A referral code has already been applied to your account');
    }
    if (err instanceof ApiError) throw err;
    logger.error('[referrals] applyReferralCode failed:', err.message);
    throw ApiError.internal('Could not apply referral code');
  }

  // Let the referrer know a friend joined with their code.
  try {
    await notify(referrer.id, {
      type: 'REFERRAL',
      title: 'You referred a friend!',
      body: `${applicant.fullName || 'A new user'} joined using your code. You'll earn ₹${Number(rewardAmount)} after their first completed booking.`,
      data: { referralId: referral.id, referredUserId: userId },
    });
  } catch (err) {
    logger.debug(`[referrals] apply notify skipped: ${err.message}`);
  }

  return {
    id: referral.id,
    status: referral.status,
    rewardAmount: Number(D(referral.rewardAmount)),
    referrer: { id: referrer.id, name: referrer.fullName },
  };
}

export default { getMyReferrals, applyReferralCode };
