// Thin HTTP handlers for the support tickets domain.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import * as supportService from '../services/support.service.js';

/** POST /support/tickets — open a ticket. */
export const createTicket = asyncHandler(async (req, res) => {
  const ticket = await supportService.createTicket({
    user: req.user,
    subject: req.body.subject,
    description: req.body.description,
    priority: req.body.priority,
  });
  return created(res, ticket);
});

/** GET /support/tickets — list mine. `?status` optional. */
export const listTickets = asyncHandler(async (req, res) => {
  const { skip, take, page, limit } = getPagination(req);
  const { data, total } = await supportService.listTickets({
    userId: req.user.id,
    skip,
    take,
    status: req.query.status,
  });
  return ok(res, data, buildMeta(total, page, limit));
});

/** GET /support/tickets/:id — ticket with messages. */
export const getTicket = asyncHandler(async (req, res) => {
  const ticket = await supportService.getTicket({
    ticketId: req.params.id,
    userId: req.user.id,
  });
  return ok(res, ticket);
});

/** POST /support/tickets/:id/messages — add a message. */
export const addMessage = asyncHandler(async (req, res) => {
  const message = await supportService.addMessage({
    ticketId: req.params.id,
    user: req.user,
    message: req.body.message,
  });
  return created(res, message);
});

/** GET /support/chat — the user's live support chat thread. */
export const getChat = asyncHandler(async (req, res) => {
  const chat = await supportService.getSupportChat(req.user);
  return ok(res, chat);
});

/** POST /support/chat/messages — send a message in the live support chat. */
export const postChatMessage = asyncHandler(async (req, res) => {
  const result = await supportService.addChatMessage({
    user: req.user,
    message: req.body.message,
  });
  return created(res, result);
});

export default {
  createTicket,
  listTickets,
  getTicket,
  addMessage,
  getChat,
  postChatMessage,
};
