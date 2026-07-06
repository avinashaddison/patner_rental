// Express application assembly.
// Mounts security middleware, raw-body parsing for the Razorpay webhook (BEFORE json),
// the JSON parser, rate limiting, auto-loaded feature routes, /health, /api docs,
// and the 404 + error handlers.
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';
import { config } from './config/index.js';
import { logger } from './lib/logger.js';
import { mountRoutes } from './routes/index.js';
import { notFound, errorHandler } from './middleware/error.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { CATEGORIES, BOOKING_DURATIONS } from './config/constants.js';

export async function createApp() {
  const app = express();

  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(
    cors({
      origin(origin, cb) {
        // Allow same-origin / server-to-server (no origin) and configured origins.
        if (!origin || config.corsOrigins.includes(origin)) return cb(null, true);
        return cb(null, false);
      },
      credentials: true,
    }),
  );
  app.use(morgan(config.isProd ? 'combined' : 'dev', { stream: logger.stream }));

  // Razorpay webhook needs the raw body for signature verification — register the
  // raw parser for that exact path BEFORE the global JSON parser.
  app.use('/api/payments/webhook', express.raw({ type: 'application/json' }));

  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: true }));

  // Global API rate limit.
  app.use('/api', apiLimiter);

  // Liveness.
  app.get('/health', (_req, res) => {
    res.json({ success: true, data: { status: 'ok', service: config.appName, time: new Date().toISOString() } });
  });

  // Public meta config (also exposed under /api/meta by a feature route if present).
  app.get('/api', (_req, res) => {
    res.json({
      success: true,
      data: {
        service: config.appName,
        version: '1.0.0',
        docs: '/api docs in repo: docs/API.md',
        categories: CATEGORIES.map((c) => c.slug),
        bookingDurations: BOOKING_DURATIONS,
        commissionRate: config.business.commissionRate,
        minAge: config.business.minAge,
      },
    });
  });

  // Auto-mount every src/routes/*.routes.js at /api/<name>.
  await mountRoutes(app);

  // Fallbacks.
  app.use(notFound);
  app.use(errorHandler);

  return app;
}

export default createApp;
