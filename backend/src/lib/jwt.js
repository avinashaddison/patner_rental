// JWT helpers for user access/refresh tokens and admin tokens.
// Access tokens are short-lived (15m), refresh tokens long-lived (30d).
import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';

const { jwt: jwtConfig } = config;

export function signAccessToken(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, type: 'access' },
    jwtConfig.accessSecret,
    { expiresIn: jwtConfig.accessTtl },
  );
}

export function signRefreshToken(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, type: 'refresh' },
    jwtConfig.refreshSecret,
    { expiresIn: jwtConfig.refreshTtl },
  );
}

export function verifyAccessToken(token) {
  const payload = jwt.verify(token, jwtConfig.accessSecret);
  if (payload.type && payload.type !== 'access') {
    throw new Error('Invalid token type');
  }
  return payload;
}

export function verifyRefreshToken(token) {
  const payload = jwt.verify(token, jwtConfig.refreshSecret);
  if (payload.type && payload.type !== 'refresh') {
    throw new Error('Invalid token type');
  }
  return payload;
}

export function signAdminToken(admin) {
  return jwt.sign(
    { sub: admin.id, role: admin.role, type: 'admin', email: admin.email },
    jwtConfig.adminSecret,
    { expiresIn: jwtConfig.accessTtl },
  );
}

export function verifyAdminToken(token) {
  const payload = jwt.verify(token, jwtConfig.adminSecret);
  if (payload.type !== 'admin') {
    throw new Error('Invalid admin token');
  }
  return payload;
}

export default {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  signAdminToken,
  verifyAdminToken,
};
