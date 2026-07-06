// Authentication + authorization middleware.
// requireAuth / optionalAuth set req.user; requireAdmin sets req.admin.
import { verifyAccessToken, verifyAdminToken } from '../lib/jwt.js';
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function extractToken(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) return header.slice(7).trim();
  return null;
}

// Every authenticated request reloads the user (+companion join) from the DB —
// at ~1.8s/round-trip to the remote Postgres that is the single biggest latency
// tax in the app. Cache the loaded user briefly so the burst of calls one screen
// makes (list + detail + counts) costs one query, not one each. TTL is short so
// role/block changes take effect within seconds; block/unblock invalidate now.
const _userCache = new Map(); // userId -> { user, at(ms) }
const USER_TTL_MS = 8_000;

/** Drop a user from the auth cache (call after block/unblock/role/profile edits). */
export function invalidateUserCache(userId) {
  if (userId) _userCache.delete(userId);
}

async function loadUserCached(userId) {
  const hit = _userCache.get(userId);
  if (hit && Date.now() - hit.at < USER_TTL_MS) return hit.user;
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { companion: true },
  });
  _userCache.set(userId, { user, at: Date.now() });
  return user;
}

/** Require a valid user access token. Loads the user (with companion) onto req.user. */
export const requireAuth = asyncHandler(async (req, _res, next) => {
  const token = extractToken(req);
  if (!token) throw ApiError.unauthorized('Missing access token');

  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch {
    throw ApiError.unauthorized('Invalid or expired token');
  }

  const user = await loadUserCached(payload.sub);
  if (!user) throw ApiError.unauthorized('User not found');
  if (user.isBlocked) throw ApiError.forbidden(user.blockedReason || 'Account is blocked');

  req.user = user;
  req.token = token;
  next();
});

/** Attach req.user if a valid token is present; otherwise continue anonymously. */
export const optionalAuth = asyncHandler(async (req, _res, next) => {
  const token = extractToken(req);
  if (!token) return next();
  try {
    const payload = verifyAccessToken(token);
    const user = await loadUserCached(payload.sub);
    if (user && !user.isBlocked) {
      req.user = user;
      req.token = token;
    }
  } catch {
    // ignore — anonymous request
  }
  next();
});

/** Restrict a route to one or more user roles. Must run after requireAuth. */
export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(ApiError.unauthorized());
    if (!roles.includes(req.user.role)) {
      return next(ApiError.forbidden(`Requires role: ${roles.join(' or ')}`));
    }
    return next();
  };
}

/** Require a valid admin token. Loads the admin onto req.admin. */
export const requireAdmin = asyncHandler(async (req, _res, next) => {
  const token = extractToken(req);
  if (!token) throw ApiError.unauthorized('Missing admin token');

  let payload;
  try {
    payload = verifyAdminToken(token);
  } catch {
    throw ApiError.unauthorized('Invalid or expired admin token');
  }

  const admin = await prisma.adminUser.findUnique({ where: { id: payload.sub } });
  if (!admin || !admin.isActive) throw ApiError.unauthorized('Admin not found or inactive');

  req.admin = admin;
  req.token = token;
  next();
});

export default { requireAuth, optionalAuth, requireRole, requireAdmin, invalidateUserCache };
