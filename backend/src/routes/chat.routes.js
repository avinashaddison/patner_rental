// Chat (REST) routes — auto-mounted at /api/chat.
// Realtime is handled by Socket.IO (src/lib/socket.js); these are the REST equivalents.
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import {
  createConversationSchema,
  sendMessageSchema,
  conversationIdParam,
} from '../validators/chat.validator.js';
import * as chat from '../controllers/chat.controller.js';

const router = Router();

router.use(requireAuth);

router.get('/conversations', chat.listConversations);
router.post('/conversations', validate(createConversationSchema), chat.createConversation);
router.get(
  '/conversations/:id/messages',
  validate(conversationIdParam, 'params'),
  chat.listMessages,
);
router.post(
  '/conversations/:id/messages',
  validate(conversationIdParam, 'params'),
  validate(sendMessageSchema),
  chat.sendMessage,
);
router.post(
  '/conversations/:id/read',
  validate(conversationIdParam, 'params'),
  chat.markRead,
);

export default router;
