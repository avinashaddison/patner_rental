// HTTP + Socket.IO server bootstrap with graceful shutdown.
import http from 'http';
import { createApp } from './app.js';
import { initSocket } from './lib/socket.js';
import { startMailWatcher, stopMailWatcher } from './lib/mailwatcher.js';
import { prisma } from './lib/prisma.js';
import { config } from './config/index.js';
import { logger } from './lib/logger.js';

async function main() {
  const app = await createApp();
  const server = http.createServer(app);

  // Attach realtime layer (chat + presence).
  initSocket(server);

  // Bank-email watcher for self-hosted UPI QR payments (no-op if unconfigured).
  startMailWatcher();

  server.listen(config.port, () => {
    logger.info(`${config.appName} backend listening on :${config.port} (${config.env})`);
    logger.info(`Health:  ${config.apiBaseUrl}/health`);
    logger.info(`API:     ${config.apiBaseUrl}/api`);
  });

  // --- Graceful shutdown ---
  let shuttingDown = false;
  const shutdown = async (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info(`Received ${signal}, shutting down gracefully...`);

    server.close(() => logger.info('HTTP server closed.'));
    await stopMailWatcher().catch(() => {});

    try {
      await prisma.$disconnect();
      logger.info('Prisma disconnected.');
    } catch (err) {
      logger.error('Error during Prisma disconnect:', err.message);
    }

    // Force-exit if connections linger.
    setTimeout(() => process.exit(0), 5000).unref();
    process.exit(0);
  };

  ['SIGINT', 'SIGTERM'].forEach((sig) => process.on(sig, () => shutdown(sig)));

  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection:', reason);
  });
  process.on('uncaughtException', (err) => {
    logger.error('Uncaught exception:', err);
  });

  return server;
}

main().catch((err) => {
  logger.error('Fatal startup error:', err);
  process.exit(1);
});
