// Zod request schemas for the support tickets domain.
import { z } from 'zod';

const TICKET_PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'];

/** POST /support/tickets — open a ticket. */
export const createTicketSchema = z.object({
  subject: z.string().trim().min(3, 'Subject is too short').max(200),
  description: z.string().trim().min(5, 'Description is too short').max(5000),
  priority: z.enum(TICKET_PRIORITIES).optional().default('MEDIUM'),
});

/** POST /support/tickets/:id/messages — add a message to a ticket. */
export const ticketMessageSchema = z.object({
  message: z.string().trim().min(1, 'Message is required').max(5000),
});

/** :id path param for a ticket. */
export const ticketIdParam = z.object({ id: z.string().uuid('Invalid id') });

export default { createTicketSchema, ticketMessageSchema, ticketIdParam, TICKET_PRIORITIES };
