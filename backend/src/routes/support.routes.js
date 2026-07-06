// Support tickets routes — auto-mounted at /api/support.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import {
  createTicketSchema,
  ticketMessageSchema,
  ticketIdParam,
} from '../validators/support.validator.js';
import * as support from '../controllers/support.controller.js';

const router = Router();

router.use(requireAuth);

// Live support chat (single continuous thread, surfaced in the app Chat tab).
router.get('/chat', support.getChat);
router.post('/chat/messages', validate(ticketMessageSchema), support.postChatMessage);

router.post('/tickets', validate(createTicketSchema), support.createTicket);
router.get('/tickets', support.listTickets);
router.get('/tickets/:id', validate(ticketIdParam, 'params'), support.getTicket);
router.post(
  '/tickets/:id/messages',
  validate(ticketIdParam, 'params'),
  validate(ticketMessageSchema),
  support.addMessage,
);

export default router;
