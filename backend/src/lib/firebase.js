// Firebase Admin (FCM push). Lazily initialized from FIREBASE_SERVICE_ACCOUNT.
// If not configured, all push calls become graceful no-ops so the app still runs.
import fs from 'fs';
import admin from 'firebase-admin';
import { config } from '../config/index.js';
import { logger } from './logger.js';
import { prisma } from './prisma.js';

let initialized = false;
let available = false;

function init() {
  if (initialized) return available;
  initialized = true;

  const saPath = config.firebase.serviceAccount;
  if (!saPath) {
    logger.warn('[FCM] FIREBASE_SERVICE_ACCOUNT not set; push disabled.');
    return false;
  }

  try {
    let credentialJson;
    // Allow either a file path or an inline JSON string.
    if (saPath.trim().startsWith('{')) {
      credentialJson = JSON.parse(saPath);
    } else if (fs.existsSync(saPath)) {
      credentialJson = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    } else {
      logger.warn(`[FCM] service account not found at ${saPath}; push disabled.`);
      return false;
    }

    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(credentialJson),
        projectId: config.firebase.projectId || credentialJson.project_id,
      });
    }
    available = true;
    logger.info('[FCM] firebase-admin initialized.');
  } catch (err) {
    logger.error('[FCM] init failed; push disabled:', err.message);
    available = false;
  }
  return available;
}

/**
 * Verify a Firebase ID token (Phone Auth). Throws if Firebase isn't configured
 * (code `firebase/not-configured`) or the token is invalid/expired. On success
 * returns the decoded token, including `phone_number` (E.164).
 */
export async function verifyIdToken(idToken) {
  if (!init()) {
    const err = new Error('Firebase not configured');
    err.code = 'firebase/not-configured';
    throw err;
  }
  return admin.auth().verifyIdToken(idToken);
}

/**
 * Send a push to a single device token.
 * @returns {Promise<{sent:boolean, reason?:string}>}
 */
export async function sendPush({ token, title, body, data = {} }) {
  if (!token) return { sent: false, reason: 'no_token' };
  if (!init()) return { sent: false, reason: 'not_configured' };

  // FCM data payload must be string values only.
  const stringData = Object.fromEntries(
    Object.entries(data || {}).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)]),
  );

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: stringData,
      android: {
        priority: 'high',
        notification: {
          // Route through the app's custom-sound channel (created client-side,
          // see push_service.dart kAlertsChannelId). On Android 8+ the channel
          // owns the sound; `sound` also covers older versions.
          channelId: 'companion_alerts_v1',
          sound: 'companion_notify',
        },
      },
    });
    return { sent: true };
  } catch (err) {
    logger.warn(`[FCM] send failed for token: ${err.message}`);
    return { sent: false, reason: err.message };
  }
}

/**
 * Look up a user's fcmToken and push to it.
 */
export async function sendPushToUser(userId, { title, body, data = {} }) {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true },
    });
    if (!user?.fcmToken) return { sent: false, reason: 'no_token' };
    return sendPush({ token: user.fcmToken, title, body, data });
  } catch (err) {
    logger.warn(`[FCM] sendPushToUser failed for ${userId}: ${err.message}`);
    return { sent: false, reason: err.message };
  }
}

export default { sendPush, sendPushToUser, verifyIdToken };
