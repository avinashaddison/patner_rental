// Wallet ledger — the single source of truth for money movement.
// Every change goes through a Prisma transaction, updates wallet balances, and
// writes an immutable Transaction row. All math uses Prisma.Decimal (never floats).
import pkg from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { getReferralReward } from './settings.service.js';
import { logger } from '../lib/logger.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

/** Round a Decimal to 2 dp (INR paise precision). */
export function round2(value) {
  return D(value).toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
}

/** Ensure the user has a wallet row; returns it (inside tx if provided). */
async function ensureWallet(userId, client = prisma) {
  const existing = await client.wallet.findUnique({ where: { userId } });
  if (existing) return existing;
  return client.wallet.create({ data: { userId } });
}

/**
 * Credit a wallet. Increases balance + totalEarned, writes a CREDIT-like transaction.
 * @param {{userId, amount, type, bookingId?, description?, reference?, client?}} args
 */
export async function creditWallet({ userId, amount, type = 'CREDIT', bookingId = null, description = null, reference = null, client = null }) {
  const amt = round2(amount);
  if (amt.lte(0)) throw new Error('creditWallet: amount must be positive');

  const run = async (tx) => {
    const wallet = await ensureWallet(userId, tx);
    const newBalance = round2(D(wallet.balance).plus(amt));
    const newTotalEarned = round2(D(wallet.totalEarned).plus(amt));
    await tx.wallet.update({
      where: { id: wallet.id },
      data: { balance: newBalance, totalEarned: newTotalEarned },
    });
    return tx.transaction.create({
      data: {
        walletId: wallet.id,
        userId,
        bookingId,
        type,
        amount: amt,
        balanceAfter: newBalance,
        status: 'COMPLETED',
        reference,
        description,
      },
    });
  };

  return client ? run(client) : prisma.$transaction(run);
}

/**
 * Debit a wallet. Decreases balance; writes a signed-negative transaction.
 * Throws on insufficient balance.
 * @param {{userId, amount, type, bookingId?, description?, reference?, client?}} args
 */
export async function debitWallet({ userId, amount, type = 'DEBIT', bookingId = null, description = null, reference = null, client = null }) {
  const amt = round2(amount);
  if (amt.lte(0)) throw new Error('debitWallet: amount must be positive');

  const run = async (tx) => {
    const wallet = await ensureWallet(userId, tx);
    if (D(wallet.balance).lt(amt)) {
      const e = new Error('Insufficient wallet balance');
      e.code = 'INSUFFICIENT_BALANCE';
      throw e;
    }
    const newBalance = round2(D(wallet.balance).minus(amt));
    await tx.wallet.update({ where: { id: wallet.id }, data: { balance: newBalance } });
    return tx.transaction.create({
      data: {
        walletId: wallet.id,
        userId,
        bookingId,
        type,
        amount: amt.negated(),
        balanceAfter: newBalance,
        status: 'COMPLETED',
        reference,
        description,
      },
    });
  };

  return client ? run(client) : prisma.$transaction(run);
}

/**
 * On booking COMPLETED: credit the companion's payout as BOOKING_EARNING and
 * bump companion.totalEarnings.
 * @param {object} booking  a booking row (must include companionId, companionPayout)
 */
export async function creditCompanionEarning(booking) {
  return prisma.$transaction(async (tx) => {
    const companion = await tx.companion.findUnique({ where: { id: booking.companionId } });
    if (!companion) throw new Error('creditCompanionEarning: companion not found');

    const txn = await creditWallet({
      userId: companion.userId,
      amount: booking.companionPayout,
      type: 'BOOKING_EARNING',
      bookingId: booking.id,
      description: `Earning for booking ${booking.bookingCode}`,
      reference: booking.bookingCode,
      client: tx,
    });

    await tx.companion.update({
      where: { id: companion.id },
      data: {
        totalEarnings: round2(D(companion.totalEarnings).plus(round2(booking.companionPayout))),
        totalBookings: { increment: 1 },
      },
    });

    return txn;
  });
}

/**
 * Record the platform commission for a completed booking as a ledger entry
 * against the companion's wallet (informational COMMISSION transaction, no balance change).
 */
export async function recordCommission(booking) {
  const companion = await prisma.companion.findUnique({ where: { id: booking.companionId } });
  if (!companion) throw new Error('recordCommission: companion not found');
  const wallet = await ensureWallet(companion.userId);
  return prisma.transaction.create({
    data: {
      walletId: wallet.id,
      userId: companion.userId,
      bookingId: booking.id,
      type: 'COMMISSION',
      amount: round2(booking.commissionAmount).negated(),
      balanceAfter: round2(wallet.balance),
      status: 'COMPLETED',
      reference: booking.bookingCode,
      description: `Platform commission (${booking.commissionRate}%) for booking ${booking.bookingCode}`,
    },
  });
}

/**
 * Settle a COMPLETED cash (pay-in-person) booking. The companion collected the
 * full amount in cash, so — unlike an online booking — we do NOT credit their
 * wallet with the payout. We just mark the payment CAPTURED and bump lifetime
 * stats. The platform commission is recorded separately (recordCommission) for
 * reporting; actually collecting it from the companion is a future enhancement.
 * @param {object} booking  row with id, companionId, companionPayout, bookingCode
 */
export async function settleCashBooking(booking) {
  return prisma.$transaction(async (tx) => {
    const companion = await tx.companion.findUnique({ where: { id: booking.companionId } });
    if (!companion) throw new Error('settleCashBooking: companion not found');

    await tx.payment.updateMany({
      where: { bookingId: booking.id },
      data: { status: 'CAPTURED', capturedAt: new Date() },
    });

    await tx.companion.update({
      where: { id: companion.id },
      data: {
        totalEarnings: round2(
          D(companion.totalEarnings).plus(round2(booking.companionPayout)),
        ),
        totalBookings: { increment: 1 },
      },
    });
  });
}

/**
 * Refund a customer for a paid booking. Credits totalAmount back to their wallet
 * as a REFUND transaction and updates payment + booking status.
 * Razorpay gateway refund (if any) is handled by the payments layer; this is the
 * ledger side and the wallet-credit fallback.
 */
export async function refundToCustomer(booking) {
  return prisma.$transaction(async (tx) => {
    const txn = await creditWallet({
      userId: booking.customerId,
      amount: booking.totalAmount,
      type: 'REFUND',
      bookingId: booking.id,
      description: `Refund for booking ${booking.bookingCode}`,
      reference: booking.bookingCode,
      client: tx,
    });

    await tx.payment.updateMany({
      where: { bookingId: booking.id },
      data: { status: 'REFUNDED' },
    });

    return txn;
  });
}

/**
 * Evaluate + apply the referral reward on a referee's FIRST completed booking.
 * Credits the referrer ₹reward and marks the referral COMPLETED. Idempotent.
 * @param {string} customerId  the referee (person who was referred)
 * @param {object} booking
 */
export async function applyReferralRewardIfEligible(customerId, booking) {
  const referral = await prisma.referral.findUnique({ where: { referredId: customerId } });
  if (!referral || referral.rewarded || referral.status === 'COMPLETED') return null;

  // Only on the referee's first COMPLETED booking.
  const completedCount = await prisma.booking.count({
    where: { customerId, status: 'COMPLETED' },
  });
  if (completedCount > 1) return null; // already had a prior completed booking

  const reward = await getReferralReward();

  try {
    return await prisma.$transaction(async (tx) => {
      // Re-check inside tx to avoid double credit under concurrency.
      const fresh = await tx.referral.findUnique({ where: { id: referral.id } });
      if (!fresh || fresh.rewarded) return null;

      const txn = await creditWallet({
        userId: referral.referrerId,
        amount: reward,
        type: 'REFERRAL_REWARD',
        bookingId: booking.id,
        description: `Referral reward for inviting a friend`,
        reference: booking.bookingCode,
        client: tx,
      });

      await tx.referral.update({
        where: { id: referral.id },
        data: {
          status: 'COMPLETED',
          rewarded: true,
          rewardAmount: round2(reward),
          qualifyingBookingId: booking.id,
          rewardedAt: new Date(),
        },
      });

      return txn;
    });
  } catch (err) {
    logger.error('[ledger] applyReferralRewardIfEligible failed:', err.message);
    return null;
  }
}

export default {
  round2,
  creditWallet,
  debitWallet,
  refundToCustomer,
  creditCompanionEarning,
  recordCommission,
  settleCashBooking,
  applyReferralRewardIfEligible,
};
