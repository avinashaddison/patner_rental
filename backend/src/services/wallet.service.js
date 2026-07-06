// Wallet + payouts business logic.
// Companions accrue earnings in their wallet; customers hold referral/refund credit.
// A payout request DEBITS the wallet immediately (funds reserved) via the ledger, and
// bumps wallet.totalWithdrawn. All money math uses Prisma.Decimal.
import pkg from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import { logger } from '../lib/logger.js';
import { round2, debitWallet } from './ledger.service.js';
import { getMinPayout } from './settings.service.js';
import { notify } from './notification.service.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

/** Ensure + return the user's wallet (creates an empty one on first access). */
async function ensureWallet(userId) {
  const existing = await prisma.wallet.findUnique({ where: { userId } });
  if (existing) return existing;
  return prisma.wallet.create({ data: { userId } });
}

/** Shape a wallet row into the API response. */
function serializeWallet(wallet) {
  return {
    balance: Number(D(wallet.balance)),
    pendingBalance: Number(D(wallet.pendingBalance)),
    totalEarned: Number(D(wallet.totalEarned)),
    totalWithdrawn: Number(D(wallet.totalWithdrawn)),
    currency: wallet.currency,
  };
}

/** GET /wallet — balances summary. */
export async function getWalletSummary(userId) {
  const wallet = await ensureWallet(userId);
  return serializeWallet(wallet);
}

/** GET /wallet/transactions — paginated immutable ledger for the user. */
export async function listTransactions(req, userId) {
  const { skip, take, page, limit } = getPagination(req);
  const where = { userId };

  const [rows, total] = await Promise.all([
    prisma.transaction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
    }),
    prisma.transaction.count({ where }),
  ]);

  const data = rows.map((t) => ({
    id: t.id,
    type: t.type,
    amount: Number(D(t.amount)),
    balanceAfter: Number(D(t.balanceAfter)),
    status: t.status,
    reference: t.reference,
    description: t.description,
    bookingId: t.bookingId,
    createdAt: t.createdAt,
  }));

  return { data, meta: buildMeta(total, page, limit) };
}

/** Shape a payout row into the API response. */
function serializePayout(p) {
  return {
    id: p.id,
    amount: Number(D(p.amount)),
    method: p.method,
    status: p.status,
    upiId: p.upiId,
    bankAccountName: p.bankAccountName,
    bankAccountNumber: p.bankAccountNumber,
    ifsc: p.ifsc,
    notes: p.notes,
    processedAt: p.processedAt,
    createdAt: p.createdAt,
  };
}

/**
 * POST /wallet/payouts — request a withdrawal (companions only).
 * Validates amount >= settings.min_payout and <= available wallet balance, then
 * debits the wallet via the ledger and records the payout as REQUESTED.
 * The debit + payout + totalWithdrawn bump happen in ONE transaction.
 */
export async function requestPayout(userId, input) {
  const amount = round2(input.amount);
  const minPayout = round2(await getMinPayout());

  if (amount.lt(minPayout)) {
    throw ApiError.badRequest(`Minimum payout is ₹${Number(minPayout)}`);
  }

  const wallet = await ensureWallet(userId);
  if (D(wallet.balance).lt(amount)) {
    throw ApiError.badRequest('Insufficient wallet balance for this payout');
  }

  let payout;
  try {
    payout = await prisma.$transaction(async (tx) => {
      // Re-read the wallet inside the tx for a consistent balance check.
      const fresh = await tx.wallet.findUnique({ where: { id: wallet.id } });
      if (!fresh || D(fresh.balance).lt(amount)) {
        throw ApiError.badRequest('Insufficient wallet balance for this payout');
      }

      // Debit reserves the funds and writes a signed-negative PAYOUT transaction.
      await debitWallet({
        userId,
        amount,
        type: 'PAYOUT',
        description: `Payout request via ${input.method}`,
        client: tx,
      });

      // Track lifetime withdrawn.
      await tx.wallet.update({
        where: { id: fresh.id },
        data: { totalWithdrawn: round2(D(fresh.totalWithdrawn).plus(amount)) },
      });

      return tx.payout.create({
        data: {
          userId,
          amount,
          method: input.method,
          upiId: input.method === 'UPI' ? input.upiId : null,
          bankAccountName: input.method === 'BANK_TRANSFER' ? input.bankAccountName : null,
          bankAccountNumber: input.method === 'BANK_TRANSFER' ? input.bankAccountNumber : null,
          ifsc: input.method === 'BANK_TRANSFER' ? input.ifsc : null,
          status: 'REQUESTED',
        },
      });
    });
  } catch (err) {
    if (err instanceof ApiError) throw err;
    if (err?.code === 'INSUFFICIENT_BALANCE') {
      throw ApiError.badRequest('Insufficient wallet balance for this payout');
    }
    logger.error('[wallet] requestPayout failed:', err.message);
    throw ApiError.internal('Could not create payout request');
  }

  try {
    await notify(userId, {
      type: 'PAYMENT',
      title: 'Payout requested',
      body: `Your payout request of ₹${Number(amount)} is being processed.`,
      data: { payoutId: payout.id, amount: Number(amount) },
    });
  } catch (err) {
    logger.debug(`[wallet] payout notify skipped: ${err.message}`);
  }

  return serializePayout(payout);
}

/** GET /wallet/payouts — payout history (paginated). */
export async function listPayouts(req, userId) {
  const { skip, take, page, limit } = getPagination(req);
  const where = { userId };

  const [rows, total] = await Promise.all([
    prisma.payout.findMany({ where, orderBy: { createdAt: 'desc' }, skip, take }),
    prisma.payout.count({ where }),
  ]);

  return { data: rows.map(serializePayout), meta: buildMeta(total, page, limit) };
}

export default {
  getWalletSummary,
  listTransactions,
  requestPayout,
  listPayouts,
};
