// Read-side service for a user's own notifications feed.
// Creation/fan-out lives in services/notification.service.js (the shared `notify`).
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';

/** Paginated notifications for a user (newest first), optionally filtered by unread. */
export async function listNotifications({ userId, skip, take, unreadOnly = false }) {
  const where = { userId };
  if (unreadOnly) where.isRead = false;

  const [total, data] = await Promise.all([
    prisma.notification.count({ where }),
    prisma.notification.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
    }),
  ]);

  return { data, total };
}

/** Mark a single notification read (must belong to the user). */
export async function markRead({ notificationId, userId }) {
  const notification = await prisma.notification.findUnique({ where: { id: notificationId } });
  if (!notification || notification.userId !== userId) {
    throw ApiError.notFound('Notification not found');
  }
  if (notification.isRead) return notification;
  return prisma.notification.update({
    where: { id: notificationId },
    data: { isRead: true },
  });
}

/** Mark all of a user's notifications read. */
export async function markAllRead(userId) {
  const result = await prisma.notification.updateMany({
    where: { userId, isRead: false },
    data: { isRead: true },
  });
  return { marked: result.count };
}

/** Count unread notifications for a user. */
export async function unreadCount(userId) {
  const count = await prisma.notification.count({ where: { userId, isRead: false } });
  return { count };
}

export default { listNotifications, markRead, markAllRead, unreadCount };
