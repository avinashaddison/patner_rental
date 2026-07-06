// Voice/video calls (Agora RTC). The socket layer does the ringing
// (call:invite → call:incoming → call:accepted/rejected/ended, see
// lib/socket.js); this route only mints the per-channel RTC token both
// parties use to join the media channel. Channel name = `conv_<id>` so a
// call is always scoped to an existing conversation the user belongs to —
// nobody can call a stranger.
import { Router } from 'express';
import agoraToken from 'agora-token'; // CJS module — no named exports.

const { RtcTokenBuilder, RtcRole } = agoraToken;
import { prisma } from '../lib/prisma.js';
import { config } from '../config/index.js';
import { requireAuth } from '../middleware/auth.js';
import { ApiError, ok } from '../utils/apiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';

const router = Router();

// Tokens are short-lived: calls re-request on (re)join.
const TOKEN_TTL_SECONDS = 60 * 60; // 1 hour

router.post(
  '/token',
  requireAuth,
  asyncHandler(async (req, res) => {
    if (!config.agora.enabled) {
      throw ApiError.internal('Calling is not configured on the server.');
    }
    const conversationId = String(req.body?.conversationId || '');
    if (!conversationId) {
      throw ApiError.badRequest('conversationId is required');
    }

    const convo = await prisma.conversation.findUnique({
      where: { id: conversationId },
    });
    if (
      !convo ||
      (convo.customerId !== req.user.id && convo.companionId !== req.user.id)
    ) {
      throw ApiError.forbidden('You are not part of this conversation.');
    }

    const channel = `conv_${conversationId}`;
    const now = Math.floor(Date.now() / 1000);
    const expireAt = now + TOKEN_TTL_SECONDS;
    const token = RtcTokenBuilder.buildTokenWithUserAccount(
      config.agora.appId,
      config.agora.appCertificate,
      channel,
      req.user.id, // string user account = our user id
      RtcRole.PUBLISHER,
      expireAt,
      expireAt,
    );

    return ok(res, {
      token,
      channel,
      userAccount: req.user.id,
      appId: config.agora.appId,
      expiresAt: expireAt,
    });
  }),
);

export default router;
