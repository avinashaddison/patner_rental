// Chat business logic: conversations + messages.
// A conversation row is between two USERS (customerId + companionId are both user ids,
// per the Conversation model). Resolution of which side is which is role-aware: the
// COMPANION-role participant is stored as companionId, the other as customerId. The
// (customerId, companionId) unique pair is directional, so get-or-create also checks
// the reverse direction to avoid duplicates.
import { prisma } from '../lib/prisma.js';
import { emitToUser } from '../lib/socket.js';
import { ApiError } from '../utils/apiResponse.js';
import { notify } from './notification.service.js';

/** True if either user has blocked the other. */
export async function isBlockedBetween(userIdA, userIdB) {
  const block = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: userIdA, blockedId: userIdB },
        { blockerId: userIdB, blockedId: userIdA },
      ],
    },
    select: { id: true },
  });
  return Boolean(block);
}

/** The other participant's user id for a conversation. */
export function peerOf(conversation, userId) {
  return conversation.customerId === userId ? conversation.companionId : conversation.customerId;
}

/** Throw FORBIDDEN unless userId participates in the conversation. */
function assertParticipant(conversation, userId) {
  if (!conversation) throw ApiError.notFound('Conversation not found');
  if (conversation.customerId !== userId && conversation.companionId !== userId) {
    throw ApiError.forbidden('Not a participant of this conversation');
  }
}

/**
 * Decide the (customerId, companionId) ordering for a user pair. The participant
 * whose user.role is COMPANION becomes companionId; otherwise the requester is the
 * customer side. This keeps the directional unique pair stable for a given pair.
 */
function orderParticipants(meId, meRole, peerId, peerRole) {
  // Companion-role participant is the "companion side".
  if (peerRole === 'COMPANION' && meRole !== 'COMPANION') {
    return { customerId: meId, companionId: peerId };
  }
  if (meRole === 'COMPANION' && peerRole !== 'COMPANION') {
    return { customerId: peerId, companionId: meId };
  }
  // Neither or both are companions: keep requester as customer side (deterministic enough;
  // reverse-direction lookup below prevents duplicates).
  return { customerId: meId, companionId: peerId };
}

/** Build a lightweight participant snapshot used in conversation payloads. */
function publicUser(u) {
  if (!u) return null;
  return {
    id: u.id,
    fullName: u.fullName,
    profilePhotoUrl: u.profilePhotoUrl,
    role: u.role,
  };
}

/**
 * Get an existing conversation for a user pair (in either direction), or create one.
 * Block-aware: refuses if either party blocked the other.
 */
export async function getOrCreateConversation({ me, peerUserId, bookingId }) {
  if (peerUserId === me.id) {
    throw ApiError.badRequest('Cannot start a conversation with yourself');
  }

  const peer = await prisma.user.findUnique({
    where: { id: peerUserId },
    select: { id: true, role: true, fullName: true, profilePhotoUrl: true, isBlocked: true },
  });
  if (!peer) throw ApiError.notFound('Peer user not found');

  if (await isBlockedBetween(me.id, peerUserId)) {
    throw ApiError.forbidden('Messaging is unavailable between you and this user');
  }

  // Look for an existing conversation in either direction.
  let conversation = await prisma.conversation.findFirst({
    where: {
      OR: [
        { customerId: me.id, companionId: peerUserId },
        { customerId: peerUserId, companionId: me.id },
      ],
    },
  });

  if (!conversation) {
    const { customerId, companionId } = orderParticipants(me.id, me.role, peer.id, peer.role);
    try {
      conversation = await prisma.conversation.create({
        data: { customerId, companionId, bookingId: bookingId || null },
      });
    } catch (err) {
      // Unique race: fetch the row created by the concurrent request.
      if (err.code === 'P2002') {
        conversation = await prisma.conversation.findFirst({
          where: {
            OR: [
              { customerId: me.id, companionId: peerUserId },
              { customerId: peerUserId, companionId: me.id },
            ],
          },
        });
      }
      if (!conversation) throw err;
    }
  } else if (bookingId && !conversation.bookingId) {
    // Backfill the booking link if newly provided.
    conversation = await prisma.conversation.update({
      where: { id: conversation.id },
      data: { bookingId },
    });
  }

  return decorateConversation(conversation, me.id);
}

/** Attach peer snapshot + unread count to a single conversation. */
async function decorateConversation(conversation, userId) {
  const peerId = peerOf(conversation, userId);
  const [peer, unreadCount] = await Promise.all([
    prisma.user.findUnique({
      where: { id: peerId },
      select: { id: true, fullName: true, profilePhotoUrl: true, role: true },
    }),
    prisma.message.count({
      where: { conversationId: conversation.id, receiverId: userId, isRead: false },
    }),
  ]);
  return {
    id: conversation.id,
    customerId: conversation.customerId,
    companionId: conversation.companionId,
    bookingId: conversation.bookingId,
    lastMessage: conversation.lastMessage,
    lastMessageAt: conversation.lastMessageAt,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    peer: publicUser(peer),
    unreadCount,
  };
}

/** List a user's conversations (newest activity first) with last message + unread count. */
export async function listConversations({ userId, skip, take }) {
  const where = {
    OR: [{ customerId: userId }, { companionId: userId }],
  };

  const [total, rows] = await Promise.all([
    prisma.conversation.count({ where }),
    prisma.conversation.findMany({
      where,
      orderBy: [{ lastMessageAt: 'desc' }, { createdAt: 'desc' }],
      skip,
      take,
    }),
  ]);

  const peerIds = rows.map((c) => peerOf(c, userId));
  const peers = peerIds.length
    ? await prisma.user.findMany({
        where: { id: { in: peerIds } },
        select: {
          id: true,
          fullName: true,
          profilePhotoUrl: true,
          role: true,
          lastActiveAt: true,
        },
      })
    : [];
  const peerMap = new Map(peers.map((p) => [p.id, p]));

  // Unread counts per conversation in one grouped query.
  const grouped = rows.length
    ? await prisma.message.groupBy({
        by: ['conversationId'],
        where: {
          conversationId: { in: rows.map((c) => c.id) },
          receiverId: userId,
          isRead: false,
        },
        _count: { _all: true },
      })
    : [];
  const unreadMap = new Map(grouped.map((g) => [g.conversationId, g._count._all]));

  // Sender of the latest message per conversation (for the "You:" preview).
  const lastMsgs = rows.length
    ? await prisma.message.findMany({
        where: { conversationId: { in: rows.map((c) => c.id) } },
        orderBy: [{ conversationId: 'asc' }, { createdAt: 'desc' }],
        distinct: ['conversationId'],
        select: { conversationId: true, senderId: true },
      })
    : [];
  const lastSenderMap = new Map(lastMsgs.map((m) => [m.conversationId, m.senderId]));

  const now = Date.now();
  const ONLINE_MS = 3 * 60 * 1000; // "online" if active within 3 minutes

  const data = rows.map((c) => {
    const peer = peerMap.get(peerOf(c, userId));
    const lastActive = peer?.lastActiveAt ? new Date(peer.lastActiveAt).getTime() : null;
    return {
      id: c.id,
      customerId: c.customerId,
      companionId: c.companionId,
      bookingId: c.bookingId,
      lastMessage: c.lastMessage,
      lastMessageAt: c.lastMessageAt,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      peer: publicUser(peer),
      peerIsOnline: lastActive != null && now - lastActive < ONLINE_MS,
      peerLastActiveAt: peer?.lastActiveAt ?? null,
      lastMessageMine: lastSenderMap.get(c.id) === userId,
      unreadCount: unreadMap.get(c.id) || 0,
    };
  });

  return { data, total };
}

/** Load a conversation a user participates in, or throw. */
export async function getParticipantConversation(conversationId, userId) {
  const conversation = await prisma.conversation.findUnique({ where: { id: conversationId } });
  assertParticipant(conversation, userId);
  return conversation;
}

/** Paginated message history (newest first). */
export async function listMessages({ conversationId, userId, skip, take }) {
  await getParticipantConversation(conversationId, userId);

  const where = { conversationId };
  const [total, rows] = await Promise.all([
    prisma.message.count({ where }),
    prisma.message.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
    }),
  ]);

  return { data: rows, total };
}

/**
 * Send a message via the REST fallback. Persists, bumps the conversation, emits
 * 'message:new' to the peer, and pushes a CHAT notification when the peer is offline.
 */
export async function sendMessage({ conversationId, sender, type, content, imageUrl }) {
  const conversation = await getParticipantConversation(conversationId, sender.id);

  const receiverId = peerOf(conversation, sender.id);

  // Block-aware: do not deliver across a block.
  if (await isBlockedBetween(sender.id, receiverId)) {
    throw ApiError.forbidden('Messaging is unavailable between you and this user');
  }

  const msgType = type === 'IMAGE' ? 'IMAGE' : 'TEXT';
  const preview = msgType === 'IMAGE' ? '[Image]' : content;

  const message = await prisma.$transaction(async (tx) => {
    const created = await tx.message.create({
      data: {
        conversationId,
        senderId: sender.id,
        receiverId,
        type: msgType,
        content: msgType === 'TEXT' ? content : content || null,
        imageUrl: msgType === 'IMAGE' ? imageUrl : null,
      },
    });
    await tx.conversation.update({
      where: { id: conversationId },
      data: { lastMessage: preview, lastMessageAt: created.createdAt },
    });
    return created;
  });

  // Realtime delivery to the peer (best-effort).
  emitToUser(receiverId, 'message:new', { message });

  // Offline push fallback.
  const { isUserOnline } = await import('../lib/socket.js');
  if (!isUserOnline(receiverId)) {
    await notify(receiverId, {
      type: 'CHAT',
      title: sender.fullName || 'New message',
      body: msgType === 'IMAGE' ? 'Sent you an image' : String(content).slice(0, 120),
      data: { conversationId, messageId: message.id },
    });
  }

  return message;
}

/** Mark every inbound unread message in a conversation as read; notify the peer. */
export async function markRead({ conversationId, userId }) {
  const conversation = await getParticipantConversation(conversationId, userId);

  const result = await prisma.message.updateMany({
    where: { conversationId, receiverId: userId, isRead: false },
    data: { isRead: true, readAt: new Date() },
  });

  if (result.count > 0) {
    const peerId = peerOf(conversation, userId);
    emitToUser(peerId, 'message:read', { conversationId, userId });
  }

  return { conversationId, marked: result.count };
}

export default {
  getOrCreateConversation,
  listConversations,
  listMessages,
  sendMessage,
  markRead,
  isBlockedBetween,
  getParticipantConversation,
};
