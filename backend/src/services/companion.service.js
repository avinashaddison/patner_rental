// Companion dashboard service: earnings summary, earnings breakdown + recent ledger,
// and received-bookings views. Read-only aggregations over the companion's wallet,
// transactions, bookings, and reviews.
import pkg from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

/** Resolve the caller's companion profile or throw. */
async function requireCompanionProfile(user) {
  // req.user already includes `companion` via auth middleware, but re-read to be safe
  // and to get the freshest counters.
  const companion =
    user.companion ??
    (await prisma.companion.findUnique({ where: { userId: user.id } }));
  if (!companion) throw ApiError.notFound('Companion profile not found');
  return companion;
}

/** Ensure the companion's wallet row exists; return current balances. */
async function getWalletSnapshot(userId) {
  const wallet = await prisma.wallet.findUnique({ where: { userId } });
  return {
    balance: D(wallet?.balance).toNumber(),
    pendingBalance: D(wallet?.pendingBalance).toNumber(),
    totalEarned: D(wallet?.totalEarned).toNumber(),
    totalWithdrawn: D(wallet?.totalWithdrawn).toNumber(),
    currency: wallet?.currency ?? 'INR',
  };
}

/**
 * GET /companion/dashboard
 * @returns {{ totalEarnings, pendingEarnings, withdrawnEarnings, upcomingBookings,
 *            ratingAvg, ratingCount, reviewCount }}
 */
export async function getDashboard(user) {
  const companion = await requireCompanionProfile(user);
  const wallet = await getWalletSnapshot(user.id);

  // Pending earnings = payout value of bookings that are confirmed/in-progress
  // (money the companion will earn once those complete).
  const pendingAgg = await prisma.booking.aggregate({
    where: {
      companionId: companion.id,
      status: { in: ['CONFIRMED', 'IN_PROGRESS'] },
    },
    _sum: { companionPayout: true },
  });

  // Upcoming = confirmed bookings yet to start, today or later.
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  const upcomingBookings = await prisma.booking.count({
    where: {
      companionId: companion.id,
      status: { in: ['PENDING', 'CONFIRMED'] },
      bookingDate: { gte: today },
    },
  });

  const reviewCount = await prisma.review.count({ where: { companionId: companion.id } });

  return {
    totalEarnings: D(companion.totalEarnings).toNumber(),
    pendingEarnings: D(pendingAgg._sum.companionPayout).toNumber(),
    withdrawnEarnings: wallet.totalWithdrawn,
    upcomingBookings,
    ratingAvg: companion.ratingAvg,
    ratingCount: companion.ratingCount,
    reviewCount,
  };
}

/**
 * GET /companion/earnings — earnings breakdown + recent transactions.
 * @returns {{ summary, breakdown, recentTransactions, meta }}
 */
export async function getEarnings(user, req) {
  const companion = await requireCompanionProfile(user);
  const wallet = await getWalletSnapshot(user.id);
  const { skip, take, page, limit } = getPagination(req);

  // Sum of completed booking earnings and commission deducted, for the breakdown.
  const completedAgg = await prisma.booking.aggregate({
    where: { companionId: companion.id, status: 'COMPLETED' },
    _sum: { companionPayout: true, commissionAmount: true, totalAmount: true },
    _count: true,
  });

  const pendingAgg = await prisma.booking.aggregate({
    where: {
      companionId: companion.id,
      status: { in: ['CONFIRMED', 'IN_PROGRESS'] },
    },
    _sum: { companionPayout: true },
  });

  const [transactions, txTotal] = await prisma.$transaction([
    prisma.transaction.findMany({
      where: {
        userId: user.id,
        type: { in: ['BOOKING_EARNING', 'COMMISSION', 'PAYOUT', 'REFERRAL_REWARD', 'CREDIT', 'DEBIT'] },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take,
    }),
    prisma.transaction.count({
      where: {
        userId: user.id,
        type: { in: ['BOOKING_EARNING', 'COMMISSION', 'PAYOUT', 'REFERRAL_REWARD', 'CREDIT', 'DEBIT'] },
      },
    }),
  ]);

  return {
    summary: {
      totalEarnings: D(companion.totalEarnings).toNumber(),
      pendingEarnings: D(pendingAgg._sum.companionPayout).toNumber(),
      availableBalance: wallet.balance,
      withdrawnEarnings: wallet.totalWithdrawn,
      currency: wallet.currency,
    },
    breakdown: {
      completedBookings: completedAgg._count,
      grossEarned: D(completedAgg._sum.totalAmount).toNumber(),
      netPayout: D(completedAgg._sum.companionPayout).toNumber(),
      commissionPaid: D(completedAgg._sum.commissionAmount).toNumber(),
    },
    recentTransactions: transactions.map((t) => ({
      id: t.id,
      type: t.type,
      amount: D(t.amount).toNumber(),
      balanceAfter: D(t.balanceAfter).toNumber(),
      status: t.status,
      reference: t.reference,
      description: t.description,
      bookingId: t.bookingId,
      createdAt: t.createdAt,
    })),
    meta: buildMeta(txTotal, page, limit),
  };
}

/**
 * GET /companion/bookings — received bookings, optionally filtered by status.
 * @returns {{ items, meta }}
 */
export async function getReceivedBookings(user, req, filters = {}) {
  const companion = await requireCompanionProfile(user);
  const { skip, take, page, limit, orderBy } = getPagination(req);

  const where = { companionId: companion.id };
  if (filters.status) where.status = filters.status;

  const [rows, total] = await prisma.$transaction([
    prisma.booking.findMany({
      where,
      orderBy: orderBy ?? { createdAt: 'desc' },
      skip,
      take,
      include: {
        customer: { select: { id: true, fullName: true, profilePhotoUrl: true } },
        category: { select: { id: true, slug: true, name: true } },
        payment: { select: { id: true, status: true } },
      },
    }),
    prisma.booking.count({ where }),
  ]);

  const items = rows.map((b) => ({
    ...b,
    hourlyRate: D(b.hourlyRate).toNumber(),
    totalAmount: D(b.totalAmount).toNumber(),
    commissionAmount: D(b.commissionAmount).toNumber(),
    companionPayout: D(b.companionPayout).toNumber(),
  }));

  return { items, meta: buildMeta(total, page, limit) };
}

/**
 * PATCH /companion/location — set the companion's base coordinates. Powers
 * "near me" / distance sorting. Uses the existing Companion.latitude/longitude
 * columns (no migration).
 */
export async function updateLocation(user, { latitude, longitude }) {
  const companion = await requireCompanionProfile(user);
  await prisma.companion.update({
    where: { id: companion.id },
    data: { latitude, longitude },
  });
  return { latitude, longitude };
}

export default {
  getDashboard,
  getEarnings,
  getReceivedBookings,
  updateLocation,
};
