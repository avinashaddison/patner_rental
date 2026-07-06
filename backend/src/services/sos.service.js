// SOS (panic alert) business logic. A user raises an ACTIVE alert during/around a
// meeting; all platform admins are alerted immediately (notification + socket + log).
// Admins resolve via the admin API; the user may cancel their own active alert.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';
import { notifyAdmins } from './safety.notify.js';

/** Raise an SOS alert and fan out to admins. */
export async function createAlert({ user, bookingId, latitude, longitude, message }) {
  if (bookingId) {
    const booking = await prisma.booking.findUnique({
      where: { id: bookingId },
      select: { id: true, customerId: true, companion: { select: { userId: true } } },
    });
    if (!booking) throw ApiError.notFound('Booking not found');
    const isParticipant =
      booking.customerId === user.id || booking.companion?.userId === user.id;
    if (!isParticipant) throw ApiError.forbidden('You are not a participant of this booking');
  }

  const alert = await prisma.sosAlert.create({
    data: {
      userId: user.id,
      bookingId: bookingId || null,
      latitude: latitude ?? null,
      longitude: longitude ?? null,
      message: message || null,
      status: 'ACTIVE',
    },
  });

  // Critical safety log line.
  logger.error(
    `[SOS] ACTIVE alert ${alert.id} user=${user.id} (${user.fullName || 'unknown'}) ` +
      `booking=${bookingId || 'none'} loc=${latitude ?? '?'},${longitude ?? '?'}`,
  );

  const locStr =
    latitude != null && longitude != null ? ` near ${latitude}, ${longitude}` : '';
  await notifyAdmins({
    type: 'SOS',
    title: 'SOS ALERT — immediate attention',
    body: `${user.fullName || 'A user'} raised an SOS${locStr}.${message ? ` "${message}"` : ''}`,
    data: {
      sosId: alert.id,
      userId: user.id,
      bookingId: bookingId || null,
      latitude: latitude ?? null,
      longitude: longitude ?? null,
    },
  }).catch((err) => logger.error(`[SOS] admin notify failed: ${err.message}`));

  return alert;
}

/** List the user's active (unresolved) SOS alerts. */
export async function listActive(userId) {
  return prisma.sosAlert.findMany({
    where: { userId, status: 'ACTIVE' },
    orderBy: { createdAt: 'desc' },
  });
}

/** Cancel an active alert owned by the user. */
export async function cancelAlert({ sosId, user }) {
  const alert = await prisma.sosAlert.findUnique({ where: { id: sosId } });
  if (!alert || alert.userId !== user.id) throw ApiError.notFound('SOS alert not found');
  if (alert.status !== 'ACTIVE') {
    throw ApiError.conflict(`Alert is already ${alert.status.toLowerCase()}`);
  }

  const updated = await prisma.sosAlert.update({
    where: { id: sosId },
    data: { status: 'CANCELLED', resolvedAt: new Date() },
  });

  logger.warn(`[SOS] alert ${sosId} cancelled by user=${user.id}`);

  await notifyAdmins({
    type: 'SOS',
    title: 'SOS cancelled',
    body: `${user.fullName || 'A user'} cancelled their SOS alert.`,
    data: { sosId, userId: user.id },
  }).catch((err) => logger.debug(`[SOS] cancel notify skipped: ${err.message}`));

  return updated;
}

export default { createAlert, listActive, cancelAlert };
