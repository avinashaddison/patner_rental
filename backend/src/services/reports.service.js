// Reports / safety business logic. Customers and companions can report another user;
// admins triage via the admin API. Filing a report notifies platform admins.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';
import { notifyAdmins } from './safety.notify.js';

/** Create a report. Validates the reported user exists and (if given) the booking. */
export async function createReport({ reporterId, reportedUserId, bookingId, category, description }) {
  if (reportedUserId === reporterId) {
    throw ApiError.badRequest('You cannot report yourself');
  }

  const reported = await prisma.user.findUnique({
    where: { id: reportedUserId },
    select: { id: true, fullName: true },
  });
  if (!reported) throw ApiError.notFound('Reported user not found');

  if (bookingId) {
    const booking = await prisma.booking.findUnique({
      where: { id: bookingId },
      select: { id: true, customerId: true, companion: { select: { userId: true } } },
    });
    if (!booking) throw ApiError.notFound('Booking not found');
    const isParticipant =
      booking.customerId === reporterId || booking.companion?.userId === reporterId;
    if (!isParticipant) {
      throw ApiError.forbidden('You are not a participant of this booking');
    }
  }

  const report = await prisma.report.create({
    data: {
      reporterId,
      reportedUserId,
      bookingId: bookingId || null,
      category,
      description: description || null,
    },
  });

  logger.warn(
    `[reports] new report ${report.id} category=${category} reporter=${reporterId} reported=${reportedUserId}`,
  );

  // Alert platform admins (best-effort).
  await notifyAdmins({
    type: 'SYSTEM',
    title: 'New user report',
    body: `A ${category} report was filed against ${reported.fullName || 'a user'}.`,
    data: { reportId: report.id, reportedUserId, category },
  }).catch((err) => logger.debug(`[reports] admin notify skipped: ${err.message}`));

  return report;
}

/** List reports filed by a user (newest first). */
export async function listMyReports({ reporterId, skip, take }) {
  const where = { reporterId };
  const [total, data] = await Promise.all([
    prisma.report.count({ where }),
    prisma.report.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      include: {
        reportedUser: { select: { id: true, fullName: true, profilePhotoUrl: true } },
      },
    }),
  ]);
  return { data, total };
}

export default { createReport, listMyReports };
