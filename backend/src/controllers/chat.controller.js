// Thin HTTP handlers for the chat (REST) domain.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import * as chatService from '../services/chat.service.js';

/** GET /chat/conversations — list with last message + unread count. */
export const listConversations = asyncHandler(async (req, res) => {
  const { skip, take, page, limit } = getPagination(req);
  const { data, total } = await chatService.listConversations({
    userId: req.user.id,
    skip,
    take,
  });
  return ok(res, data, buildMeta(total, page, limit));
});

/** POST /chat/conversations — get-or-create (block-aware). */
export const createConversation = asyncHandler(async (req, res) => {
  const conversation = await chatService.getOrCreateConversation({
    me: req.user,
    peerUserId: req.body.peerUserId,
    bookingId: req.body.bookingId,
  });
  return created(res, conversation);
});

/** GET /chat/conversations/:id/messages — paginated history. */
export const listMessages = asyncHandler(async (req, res) => {
  const { skip, take, page, limit } = getPagination(req);
  const { data, total } = await chatService.listMessages({
    conversationId: req.params.id,
    userId: req.user.id,
    skip,
    take,
  });
  return ok(res, data, buildMeta(total, page, limit));
});

/** POST /chat/conversations/:id/messages — REST fallback send. */
export const sendMessage = asyncHandler(async (req, res) => {
  const message = await chatService.sendMessage({
    conversationId: req.params.id,
    sender: req.user,
    type: req.body.type,
    content: req.body.content,
    imageUrl: req.body.imageUrl,
  });
  return created(res, { message });
});

/** POST /chat/conversations/:id/read — mark read. */
export const markRead = asyncHandler(async (req, res) => {
  const result = await chatService.markRead({
    conversationId: req.params.id,
    userId: req.user.id,
  });
  return ok(res, result);
});

export default { listConversations, createConversation, listMessages, sendMessage, markRead };
