// Support tickets business logic. Users open tickets and exchange messages; admins
// reply/triage via the admin API. A reply from the user re-opens a resolved ticket.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';
import { notifyAdmins } from './safety.notify.js';

/** Open a new support ticket with the opening message recorded. */
export async function createTicket({ user, subject, description, priority }) {
  const ticket = await prisma.$transaction(async (tx) => {
    const t = await tx.supportTicket.create({
      data: {
        userId: user.id,
        subject,
        description,
        priority: priority || 'MEDIUM',
        status: 'OPEN',
      },
    });
    // Seed the thread with the user's opening message.
    await tx.ticketMessage.create({
      data: { ticketId: t.id, senderId: user.id, message: description },
    });
    return t;
  });

  await notifyAdmins({
    type: 'SYSTEM',
    title: 'New support ticket',
    body: `${user.fullName || 'A user'} opened a ticket: ${subject}`,
    data: { ticketId: ticket.id, priority: ticket.priority },
  }).catch((err) => logger.debug(`[support] admin notify skipped: ${err.message}`));

  return getTicket({ ticketId: ticket.id, userId: user.id });
}

/** List the user's tickets (newest first). */
export async function listTickets({ userId, skip, take, status }) {
  const where = { userId };
  if (status) where.status = status;

  const [total, data] = await Promise.all([
    prisma.supportTicket.count({ where }),
    prisma.supportTicket.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      skip,
      take,
      include: { _count: { select: { messages: true } } },
    }),
  ]);

  return { data, total };
}

/** Fetch a ticket (owned by the user) with its full message thread. */
export async function getTicket({ ticketId, userId }) {
  const ticket = await prisma.supportTicket.findUnique({
    where: { id: ticketId },
    include: {
      messages: {
        orderBy: { createdAt: 'asc' },
        include: { sender: { select: { id: true, fullName: true, role: true } } },
      },
    },
  });
  if (!ticket || ticket.userId !== userId) throw ApiError.notFound('Ticket not found');
  return ticket;
}

/** Append a message from the user to a ticket; re-opens a resolved/closed ticket. */
export async function addMessage({ ticketId, user, message }) {
  const ticket = await prisma.supportTicket.findUnique({ where: { id: ticketId } });
  if (!ticket || ticket.userId !== user.id) throw ApiError.notFound('Ticket not found');

  const created = await prisma.$transaction(async (tx) => {
    const m = await tx.ticketMessage.create({
      data: { ticketId, senderId: user.id, message },
    });
    // A user reply on a resolved/closed ticket re-opens it for staff.
    const reopen = ticket.status === 'RESOLVED' || ticket.status === 'CLOSED';
    await tx.supportTicket.update({
      where: { id: ticketId },
      data: reopen ? { status: 'OPEN', resolvedAt: null } : { updatedAt: new Date() },
    });
    return m;
  });

  await notifyAdmins({
    type: 'SYSTEM',
    title: 'Support ticket reply',
    body: `${user.fullName || 'A user'} replied on: ${ticket.subject}`,
    data: { ticketId, messageId: created.id },
  }).catch((err) => logger.debug(`[support] admin notify skipped: ${err.message}`));

  return created;
}

// ---------------------------------------------------------------------------
// Live Support Chat
//
// A single, continuous chat thread between the user and the support team,
// surfaced in the app's Chat tab. It is backed by one canonical SupportTicket
// per user (subject = SUPPORT_CHAT_SUBJECT) so admins can answer it from the
// existing admin Support desk. Admin replies are pushed to the user in realtime
// (see admin.service.replyToTicket → emitToUser 'support:message').
// ---------------------------------------------------------------------------

export const SUPPORT_CHAT_SUBJECT = 'Live Support Chat';

/** Map a TicketMessage row to the chat shape the mobile app expects. */
function mapChatMessage(m, ticketUserId) {
  const fromUser = m.senderId === ticketUserId;
  return {
    id: m.id,
    message: m.message,
    role: fromUser ? 'USER' : 'SUPPORT',
    isMine: fromUser,
    createdAt: m.createdAt,
  };
}

/** The user's canonical support-chat ticket (newest), or null if none yet. */
async function findSupportChatTicket(userId) {
  return prisma.supportTicket.findFirst({
    where: { userId, subject: SUPPORT_CHAT_SUBJECT },
    orderBy: { createdAt: 'desc' },
  });
}

/**
 * Get the user's live support chat thread. Does NOT create a ticket — the
 * thread is created lazily on the first sent message, so merely opening the
 * chat never clutters the admin desk with empty tickets.
 */
export async function getSupportChat(user) {
  const ticket = await findSupportChatTicket(user.id);
  if (!ticket) {
    return { ticketId: null, status: 'OPEN', messages: [] };
  }
  const messages = await prisma.ticketMessage.findMany({
    where: { ticketId: ticket.id },
    orderBy: { createdAt: 'asc' },
  });
  return {
    ticketId: ticket.id,
    status: ticket.status,
    messages: messages.map((m) => mapChatMessage(m, user.id)),
  };
}

/** Append a user message to the live support chat, creating the thread if needed. */
export async function addChatMessage({ user, message }) {
  let ticket = await findSupportChatTicket(user.id);

  const created = await prisma.$transaction(async (tx) => {
    if (!ticket) {
      ticket = await tx.supportTicket.create({
        data: {
          userId: user.id,
          subject: SUPPORT_CHAT_SUBJECT,
          description: message.slice(0, 200),
          status: 'OPEN',
          priority: 'MEDIUM',
        },
      });
    } else {
      // A new message on a resolved/closed thread re-opens it for staff.
      const reopen = ticket.status === 'RESOLVED' || ticket.status === 'CLOSED';
      await tx.supportTicket.update({
        where: { id: ticket.id },
        data: reopen ? { status: 'OPEN', resolvedAt: null } : { updatedAt: new Date() },
      });
    }
    return tx.ticketMessage.create({
      data: { ticketId: ticket.id, senderId: user.id, message },
    });
  });

  await notifyAdmins({
    type: 'SYSTEM',
    title: 'New support message',
    body: `${user.fullName || 'A user'}: ${message.slice(0, 80)}`,
    data: { ticketId: ticket.id, messageId: created.id, kind: 'support_chat' },
  }).catch((err) => logger.debug(`[support] admin notify skipped: ${err.message}`));

  return { ticketId: ticket.id, message: mapChatMessage(created, user.id) };
}

export default {
  createTicket,
  listTickets,
  getTicket,
  addMessage,
  getSupportChat,
  addChatMessage,
  SUPPORT_CHAT_SUBJECT,
};
