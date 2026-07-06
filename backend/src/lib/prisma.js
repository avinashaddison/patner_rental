// PrismaClient singleton. Reused across the app to avoid exhausting DB connections,
// and to survive hot-reload in dev.
import { PrismaClient } from '@prisma/client';
import { config } from '../config/index.js';

const globalForPrisma = globalThis;

export const prisma =
  globalForPrisma.__companionPrisma ??
  new PrismaClient({
    log: config.isProd ? ['error', 'warn'] : ['error', 'warn'],
  });

if (!config.isProd) {
  globalForPrisma.__companionPrisma = prisma;
}

export default prisma;
