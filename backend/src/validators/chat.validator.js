// Zod request schemas for the chat (REST) domain.
import { z } from 'zod';

const uuid = z.string().uuid('Invalid id');

/** POST /chat/conversations — get-or-create a conversation with a peer user. */
export const createConversationSchema = z.object({
  peerUserId: uuid,
  bookingId: uuid.optional(),
});

/** POST /chat/conversations/:id/messages — REST fallback to send a message. */
export const sendMessageSchema = z
  .object({
    type: z
      .enum(['TEXT', 'IMAGE'])
      .optional()
      .default('TEXT'),
    content: z.string().trim().min(1).max(4000).optional(),
    imageUrl: z.string().url('imageUrl must be a valid URL').max(1000).optional(),
  })
  .superRefine((val, ctx) => {
    if (val.type === 'IMAGE') {
      if (!val.imageUrl) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['imageUrl'],
          message: 'imageUrl is required for IMAGE messages',
        });
      }
    } else if (!val.content) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['content'],
        message: 'content is required for TEXT messages',
      });
    }
  });

/** :id path param. */
export const conversationIdParam = z.object({ id: uuid });

export default { createConversationSchema, sendMessageSchema, conversationIdParam };
