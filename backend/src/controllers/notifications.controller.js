// Thin HTTP handlers for the notifications domain.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import * as notificationsService from '../services/notifications.service.js';

/** GET /notifications — paginated. `?unread=true` filters to unread. */
export const list = asyncHandler(async (req, res) => {
  const { skip, take, page, limit } = getPagination(req);
  const unreadOnly = String(req.query.unread).toLowerCase() === 'true';
  const { data, total } = await notificationsService.listNotifications({
    userId: req.user.id,
    skip,
    take,
    unreadOnly,
  });
  return ok(res, data, buildMeta(total, page, limit));
});

/** POST /notifications/:id/read. */
export const markRead = asyncHandler(async (req, res) => {
  const notification = await notificationsService.markRead({
    notificationId: req.params.id,
    userId: req.user.id,
  });
  return ok(res, notification);
});

/** POST /notifications/read-all. */
export const markAllRead = asyncHandler(async (req, res) => {
  const result = await notificationsService.markAllRead(req.user.id);
  return ok(res, result);
});

/** GET /notifications/unread-count. */
export const unreadCount = asyncHandler(async (req, res) => {
  const result = await notificationsService.unreadCount(req.user.id);
  return ok(res, result);
});

export default { list, markRead, markAllRead, unreadCount };
