// Socket.IO bootstrap: JWT-authenticated realtime layer for chat + presence.
// Handles message:send, typing:start/stop, message:read, presence:ping per docs/API.md.
// Persists messages via Prisma, tracks userId<->socket presence, and updates
// users.lastActiveAt + companion.isOnline on connect/disconnect.
import crypto from 'node:crypto';
import { Server } from 'socket.io';
import { verifyAccessToken } from './jwt.js';
import { prisma } from './prisma.js';
import { logger } from './logger.js';
import { config } from '../config/index.js';

let io = null;

// userId -> Set<socketId>
const presence = new Map();

function addPresence(userId, socketId) {
  let set = presence.get(userId);
  if (!set) {
    set = new Set();
    presence.set(userId, set);
  }
  set.add(socketId);
  return set.size;
}

function removePresence(userId, socketId) {
  const set = presence.get(userId);
  if (!set) return 0;
  set.delete(socketId);
  if (set.size === 0) presence.delete(userId);
  return set.size;
}

export function isUserOnline(userId) {
  const set = presence.get(userId);
  if (!set || set.size === 0) return false;
  // Verify at least one tracked socket is ACTUALLY still connected. Abrupt
  // client deaths (force-stop, network drop, OS kill) don't always fire a
  // 'disconnect', leaving zombie ids in the set — which would make the user
  // look permanently online and silently suppress every offline push.
  // Self-heal by pruning dead ids here.
  if (io) {
    for (const sid of set) {
      if (io.sockets.sockets.get(sid)?.connected) return true;
      set.delete(sid);
    }
  }
  if (set.size === 0) presence.delete(userId);
  return false;
}

export function getIo() {
  if (!io) throw new Error('Socket.IO not initialized. Call initSocket(server) first.');
  return io;
}

/** Emit an event to every active socket for a user. Safe no-op if io not ready. */
export function emitToUser(userId, event, payload) {
  if (!io || !userId) return;
  io.to(`user:${userId}`).emit(event, payload);
}

async function setOnlineState(userId, online) {
  try {
    await prisma.user.update({
      where: { id: userId },
      data: { lastActiveAt: new Date() },
    });
    // If this user is a companion, reflect online state on their profile.
    await prisma.companion.updateMany({
      where: { userId },
      data: { isOnline: online },
    });
  } catch (err) {
    logger.warn(`[socket] setOnlineState failed for ${userId}: ${err.message}`);
  }
}

/** Verify a peer is a participant of a conversation; returns the conversation or null. */
async function authorizeConversation(conversationId, userId) {
  const convo = await prisma.conversation.findUnique({ where: { id: conversationId } });
  if (!convo) return null;
  if (convo.customerId !== userId && convo.companionId !== userId) return null;
  return convo;
}

// Live location sharing is only permitted while a booking is in this window:
// once CONFIRMED both parties may be travelling to the meeting point, and it
// stays valid through IN_PROGRESS. Outside this (PENDING/COMPLETED/CANCELLED)
// sharing is rejected so we never track people before or after a meeting.
const TRACKABLE_BOOKING_STATUSES = new Set(['CONFIRMED', 'IN_PROGRESS']);

/**
 * Authorise a user to share/receive live location for a booking. Returns
 * `{ booking, peerUserId }` when the user is a participant AND the booking is in
 * the trackable window, otherwise null. `peerUserId` is the *other* party — the
 * only socket we relay this user's position to.
 */
async function authorizeBookingTracking(bookingId, userId) {
  if (!bookingId) return null;
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: {
      id: true,
      status: true,
      customerId: true,
      companion: { select: { userId: true } },
    },
  });
  if (!booking) return null;
  const companionUserId = booking.companion?.userId || null;
  const isParticipant =
    booking.customerId === userId || companionUserId === userId;
  if (!isParticipant) return null;
  if (!TRACKABLE_BOOKING_STATUSES.has(booking.status)) return null;
  const peerUserId =
    booking.customerId === userId ? companionUserId : booking.customerId;
  return { booking, peerUserId };
}

export function initSocket(httpServer) {
  io = new Server(httpServer, {
    cors: {
      origin: config.corsOrigins.length ? config.corsOrigins : true,
      credentials: true,
    },
  });

  // --- Auth handshake: { auth: { token } } ---
  io.use((socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.headers?.authorization?.replace(/^Bearer\s+/i, '');
      if (!token) return next(new Error('UNAUTHORIZED'));
      const payload = verifyAccessToken(token);
      socket.userId = payload.sub;
      socket.role = payload.role;
      return next();
    } catch {
      return next(new Error('UNAUTHORIZED'));
    }
  });

  io.on('connection', (socket) => {
    const userId = socket.userId;
    socket.join(`user:${userId}`);
    const count = addPresence(userId, socket.id);
    if (count === 1) {
      // Fire-and-forget: handler registration below must not wait on the DB.
      // Awaiting here opened a window where events a client emits right
      // after connecting (before registration finished) were silently lost.
      setOnlineState(userId, true)
        .then(() => io.emit('presence:update', { userId, isOnline: true }))
        .catch((err) => logger.warn(`[socket] online-state: ${err.message}`));
    }
    logger.debug(`[socket] connected user=${userId} socket=${socket.id}`);

    // --- message:send ---
    socket.on('message:send', async (payload = {}, ack) => {
      try {
        const { conversationId, type = 'TEXT', content, imageUrl, tempId } = payload;
        const convo = await authorizeConversation(conversationId, userId);
        if (!convo) {
          if (typeof ack === 'function') ack({ ok: false, error: 'FORBIDDEN' });
          return;
        }
        const msgType = String(type).toUpperCase() === 'IMAGE' ? 'IMAGE' : 'TEXT';
        if (msgType === 'TEXT' && !content) {
          if (typeof ack === 'function') ack({ ok: false, error: 'EMPTY' });
          return;
        }
        const receiverId = convo.customerId === userId ? convo.companionId : convo.customerId;

        const message = await prisma.$transaction(async (tx) => {
          const m = await tx.message.create({
            data: {
              conversationId,
              senderId: userId,
              receiverId,
              type: msgType,
              content: content || null,
              imageUrl: imageUrl || null,
            },
          });
          await tx.conversation.update({
            where: { id: conversationId },
            data: {
              lastMessage: msgType === 'IMAGE' ? '[Image]' : content,
              lastMessageAt: m.createdAt,
            },
          });
          return m;
        });

        // Deliver to receiver and echo back to sender.
        emitToUser(receiverId, 'message:new', { message });
        if (typeof ack === 'function') ack({ ok: true, message, tempId });
        socket.emit('message:sent', { tempId, message });

        // Push if receiver offline.
        if (!isUserOnline(receiverId)) {
          const { notify } = await import('../services/notification.service.js');
          await notify(receiverId, {
            type: 'CHAT',
            title: 'New message',
            body: msgType === 'IMAGE' ? 'Sent you an image' : String(content).slice(0, 120),
            data: { conversationId, messageId: message.id },
          });
        }
      } catch (err) {
        logger.error('[socket] message:send error:', err.message);
        if (typeof ack === 'function') ack({ ok: false, error: 'INTERNAL' });
      }
    });

    // --- typing indicators ---
    socket.on('typing:start', async ({ conversationId } = {}) => {
      const convo = await authorizeConversation(conversationId, userId);
      if (!convo) return;
      const receiverId = convo.customerId === userId ? convo.companionId : convo.customerId;
      emitToUser(receiverId, 'typing', { conversationId, userId, isTyping: true });
    });

    socket.on('typing:stop', async ({ conversationId } = {}) => {
      const convo = await authorizeConversation(conversationId, userId);
      if (!convo) return;
      const receiverId = convo.customerId === userId ? convo.companionId : convo.customerId;
      emitToUser(receiverId, 'typing', { conversationId, userId, isTyping: false });
    });

    // --- read receipts ---
    socket.on('message:read', async ({ conversationId } = {}) => {
      try {
        const convo = await authorizeConversation(conversationId, userId);
        if (!convo) return;
        await prisma.message.updateMany({
          where: { conversationId, receiverId: userId, isRead: false },
          data: { isRead: true, readAt: new Date() },
        });
        const peerId = convo.customerId === userId ? convo.companionId : convo.customerId;
        emitToUser(peerId, 'message:read', { conversationId, userId });
      } catch (err) {
        logger.warn('[socket] message:read error:', err.message);
      }
    });

    // --- calls: Agora signaling (ring / accept / reject / end) ---
    // Media flows through Agora; sockets only carry the call state between
    // the two conversation participants. Media tokens come from /api/calls.
    socket.on('call:invite', async ({ callId: clientCallId, conversationId, video = false } = {}, ack) => {
      try {
        const convo = await authorizeConversation(conversationId, userId);
        if (!convo) {
          if (typeof ack === 'function') ack({ ok: false, error: 'FORBIDDEN' });
          return;
        }
        const peerId =
          convo.customerId === userId ? convo.companionId : convo.customerId;
        // Keep the caller's id so both sides key signaling on the same call.
        const callId = String(clientCallId || '') || crypto.randomUUID();
        const caller = await prisma.user.findUnique({
          where: { id: userId },
          select: { fullName: true, profilePhotoUrl: true },
        });

        if (!isUserOnline(peerId)) {
          // Peer can't ring — tell the caller and leave a missed-call push.
          const { notify } = await import('../services/notification.service.js');
          await notify(peerId, {
            type: 'CHAT',
            title: caller?.fullName || 'Missed call',
            body: video ? '📹 You missed a video call' : '📞 You missed a voice call',
            data: { conversationId },
          });
          if (typeof ack === 'function') ack({ ok: true, online: false, callId });
          return;
        }

        emitToUser(peerId, 'call:incoming', {
          callId,
          conversationId,
          video: Boolean(video),
          from: {
            id: userId,
            name: caller?.fullName || 'Companion Ranchi user',
            photoUrl: caller?.profilePhotoUrl || null,
          },
        });
        if (typeof ack === 'function') ack({ ok: true, online: true, callId });
      } catch (err) {
        logger.warn(`[socket] call:invite failed: ${err.message}`);
        if (typeof ack === 'function') ack({ ok: false, error: 'ERROR' });
      }
    });

    // Relay the terminal/answer events to the other participant.
    const relayCallEvent = (inbound, outbound) => {
      socket.on(inbound, async ({ conversationId, callId } = {}) => {
        try {
          const convo = await authorizeConversation(conversationId, userId);
          if (!convo) return;
          const peerId =
            convo.customerId === userId ? convo.companionId : convo.customerId;
          emitToUser(peerId, outbound, { callId, conversationId });
        } catch (err) {
          logger.warn(`[socket] ${inbound} failed: ${err.message}`);
        }
      });
    };
    relayCallEvent('call:accept', 'call:accepted');
    relayCallEvent('call:reject', 'call:rejected');
    relayCallEvent('call:cancel', 'call:cancelled');
    relayCallEvent('call:end', 'call:ended');

    // --- presence ping (keepalive) ---
    socket.on('presence:ping', async () => {
      await prisma.user
        .update({ where: { id: userId }, data: { lastActiveAt: new Date() } })
        .catch(() => {});
      socket.emit('presence:update', { userId, isOnline: true });
    });

    // --- live location sharing (booking-scoped, opt-in) ---
    // A participant streams GPS during an active meeting so the other party can
    // navigate to the meeting point (Blinkit-style live tracking). `join`
    // authorises once (DB check) and stashes the peer on the socket; subsequent
    // `update` pings are then cheap (in-memory) and relayed only to that peer.
    socket.data.tracking = socket.data.tracking || {};

    socket.on('location:join', async ({ bookingId } = {}, ack) => {
      const ctx = await authorizeBookingTracking(bookingId, userId);
      if (!ctx) {
        if (typeof ack === 'function') ack({ ok: false, error: 'FORBIDDEN' });
        return;
      }
      socket.data.tracking[bookingId] = { peerUserId: ctx.peerUserId };
      if (typeof ack === 'function') ack({ ok: true });
      // Let the peer know live location is now available to watch.
      if (ctx.peerUserId) {
        emitToUser(ctx.peerUserId, 'location:peer-active', { bookingId, userId });
      }
    });

    socket.on('location:update', (payload = {}) => {
      const { bookingId, lat, lng, heading, speed, accuracy } = payload;
      const auth = socket.data.tracking?.[bookingId];
      if (!auth) return; // must location:join (and be authorised) first
      if (typeof lat !== 'number' || typeof lng !== 'number') return;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;
      if (!auth.peerUserId) return;
      emitToUser(auth.peerUserId, 'location:update', {
        bookingId,
        userId,
        lat,
        lng,
        heading: typeof heading === 'number' ? heading : null,
        speed: typeof speed === 'number' ? speed : null,
        accuracy: typeof accuracy === 'number' ? accuracy : null,
        at: new Date().toISOString(),
      });
    });

    socket.on('location:stop', ({ bookingId } = {}) => {
      const auth = socket.data.tracking?.[bookingId];
      if (!auth) return;
      delete socket.data.tracking[bookingId];
      if (auth.peerUserId) {
        emitToUser(auth.peerUserId, 'location:peer-stop', { bookingId, userId });
      }
    });

    // --- disconnect ---
    socket.on('disconnect', async () => {
      // Tell any peers this socket was sharing live location with that it stopped.
      const tracking = socket.data.tracking || {};
      for (const [bookingId, auth] of Object.entries(tracking)) {
        if (auth?.peerUserId) {
          emitToUser(auth.peerUserId, 'location:peer-stop', { bookingId, userId });
        }
      }
      const remaining = removePresence(userId, socket.id);
      if (remaining === 0) {
        await setOnlineState(userId, false);
        io.emit('presence:update', { userId, isOnline: false });
      }
      logger.debug(`[socket] disconnected user=${userId} socket=${socket.id}`);
    });
  });

  logger.info('[socket] Socket.IO initialized.');
  return io;
}

export default { initSocket, getIo, emitToUser, isUserOnline };
