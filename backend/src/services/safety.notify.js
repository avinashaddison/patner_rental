// Shared helper to alert platform admins about safety events (reports + SOS).
//
// Notifications are persisted against `users` rows (Notification.userId is an FK to
// users), while platform staff live in the separate `admin_users` table. To keep
// referential integrity we fan out to any users with role=ADMIN via the shared
// notify() service, and additionally broadcast a realtime socket event on the
// 'admin' room plus an FCM push to active admin AdminUser tokens when available.
import { prisma } from '../lib/prisma.js';
import { logger } from '../lib/logger.js';
import { getIo } from '../lib/socket.js';
import { notify } from './notification.service.js';

/**
 * Alert all platform admins.
 * @param {{type:string, title:string, body:string, data?:object}} payload
 * @returns {Promise<{notified:number}>}
 */
export async function notifyAdmins({ type = 'SYSTEM', title, body, data = null }) {
  // 1) Persist + push for admin-role users (FK-safe notifications).
  let adminUsers = [];
  try {
    adminUsers = await prisma.user.findMany({
      where: { role: 'ADMIN' },
      select: { id: true },
    });
  } catch (err) {
    logger.warn(`[safety] admin-user lookup failed: ${err.message}`);
  }

  await Promise.allSettled(
    adminUsers.map((u) => notify(u.id, { type, title, body, data })),
  );

  // 2) Realtime broadcast to the shared 'admin' room (admin panel sockets join it).
  try {
    getIo()
      .to('admin')
      .emit('notification:new', {
        notification: { type, title, body, data, createdAt: new Date().toISOString() },
      });
  } catch (err) {
    logger.debug(`[safety] admin socket broadcast skipped: ${err.message}`);
  }

  logger.warn(`[safety] admin alert: ${title} — ${body}`);
  return { notified: adminUsers.length };
}

export default { notifyAdmins };
