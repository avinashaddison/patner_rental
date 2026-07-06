// Notification fan-out: persist a Notification row, push via FCM, and emit a
// realtime 'notification:new' socket event to the user.
import { prisma } from '../lib/prisma.js';
import { sendPushToUser } from '../lib/firebase.js';
import { emitToUser } from '../lib/socket.js';
import { logger } from '../lib/logger.js';

const VALID_TYPES = new Set([
  'BOOKING', 'PAYMENT', 'CHAT', 'SYSTEM', 'KYC', 'REVIEW', 'REFERRAL', 'SOS',
]);

/**
 * Create + deliver a notification.
 * @param {string} userId
 * @param {{type:string, title:string, body:string, data?:object}} payload
 * @returns {Promise<object>} the persisted notification
 */
export async function notify(userId, { type, title, body, data = null }) {
  const safeType = VALID_TYPES.has(type) ? type : 'SYSTEM';

  const notification = await prisma.notification.create({
    data: {
      userId,
      type: safeType,
      title,
      body,
      data: data ?? undefined,
    },
  });

  // Realtime (best-effort).
  try {
    emitToUser(userId, 'notification:new', { notification });
  } catch (err) {
    logger.debug(`[notify] socket emit skipped: ${err.message}`);
  }

  // Push (best-effort, never throws).
  sendPushToUser(userId, {
    title,
    body,
    data: { type: safeType, notificationId: notification.id, ...(data || {}) },
  }).catch((err) => logger.debug(`[notify] push skipped: ${err.message}`));

  return notification;
}

export default { notify };
