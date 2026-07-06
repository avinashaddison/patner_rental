// Reviews business logic. A customer reviews a COMPLETED booking they own, once.
// Stores 3 sub-ratings + overall avg, then recomputes companion.ratingAvg/ratingCount.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import { notify } from './notification.service.js';
import { reviewToDto } from './companions.service.js';

/** Round to 2 decimals. */
function round2(n) {
  return Math.round(n * 100) / 100;
}

/**
 * Create a review for a completed booking.
 * @param {object} user  authenticated CUSTOMER
 * @param {{bookingId, behaviourRating, communicationRating, punctualityRating, comment?}} body
 */
export async function createReview(user, body) {
  const booking = await prisma.booking.findUnique({
    where: { id: body.bookingId },
    select: {
      id: true,
      customerId: true,
      companionId: true,
      status: true,
      bookingCode: true,
      companion: { select: { userId: true } },
    },
  });

  if (!booking) throw ApiError.notFound('Booking not found');
  if (booking.customerId !== user.id) throw ApiError.forbidden('You can only review your own bookings');
  if (booking.status !== 'COMPLETED') throw ApiError.badRequest('Only completed bookings can be reviewed');

  const existing = await prisma.review.findUnique({ where: { bookingId: booking.id } });
  if (existing) throw ApiError.conflict('You have already reviewed this booking');

  const overall = round2(
    (body.behaviourRating + body.communicationRating + body.punctualityRating) / 3
  );

  const review = await prisma.$transaction(async (tx) => {
    const created = await tx.review.create({
      data: {
        bookingId: booking.id,
        customerId: user.id,
        companionId: booking.companionId,
        behaviourRating: body.behaviourRating,
        communicationRating: body.communicationRating,
        punctualityRating: body.punctualityRating,
        overallRating: overall,
        comment: body.comment ?? null,
      },
      include: { customer: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
    });

    // Recompute the companion's aggregate rating from all reviews.
    const agg = await tx.review.aggregate({
      where: { companionId: booking.companionId },
      _avg: { overallRating: true },
      _count: { _all: true },
    });
    await tx.companion.update({
      where: { id: booking.companionId },
      data: {
        ratingAvg: round2(agg._avg.overallRating || 0),
        ratingCount: agg._count._all,
      },
    });

    return created;
  });

  // Notify the companion of the new review (best-effort).
  if (booking.companion?.userId) {
    await notify(booking.companion.userId, {
      type: 'REVIEW',
      title: 'New review received',
      body: `You received a ${overall}★ review for booking ${booking.bookingCode}.`,
      data: { bookingId: booking.id, reviewId: review.id, overallRating: overall },
    });
  }

  return reviewToDto(review);
}

/** Paginated reviews for a companion. */
export async function listForCompanion(companionId, query = {}) {
  const companion = await prisma.companion.findUnique({ where: { id: companionId }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Companion not found');

  const { skip, take, page, limit } = getPagination({ query });
  const where = { companionId };
  const [rows, total] = await Promise.all([
    prisma.review.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      include: { customer: { select: { id: true, fullName: true, profilePhotoUrl: true } } },
    }),
    prisma.review.count({ where }),
  ]);
  return { items: rows.map(reviewToDto), meta: buildMeta(total, page, limit) };
}

export default { createReview, listForCompanion };
