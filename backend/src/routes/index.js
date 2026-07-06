// Route auto-loader. Reads this directory, imports every *.routes.js, and mounts
// each Express Router at /api/<name> where name = filename without the .routes.js suffix.
// Tolerates an empty/missing folder so the app boots before feature routes exist.
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { logger } from '../lib/logger.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Discover and mount all feature routers.
 * @param {import('express').Express|import('express').Router} app
 */
export async function mountRoutes(app) {
  let files = [];
  try {
    files = fs
      .readdirSync(__dirname)
      .filter((f) => f.endsWith('.routes.js') && f !== 'index.js');
  } catch (err) {
    logger.warn(`[routes] could not read routes dir: ${err.message}`);
    return [];
  }

  const mounted = [];
  for (const file of files.sort()) {
    const name = file.replace(/\.routes\.js$/, '');
    try {
      const mod = await import(pathToFileURL(path.join(__dirname, file)).href);
      const router = mod.default;
      if (!router) {
        logger.warn(`[routes] ${file} has no default export; skipped.`);
        continue;
      }
      // Admin routes opt-in to /api/admin/<rest> via filename "admin.<x>" -> handled
      // by feature files themselves; default convention is /api/<name>.
      const mountPath = `/api/${name}`;
      app.use(mountPath, router);
      mounted.push(mountPath);
      logger.info(`[routes] mounted ${mountPath} (${file})`);
    } catch (err) {
      logger.error(`[routes] failed to mount ${file}: ${err.message}`);
    }
  }

  if (mounted.length === 0) {
    logger.warn('[routes] no feature routes found yet (this is fine for the skeleton).');
  }
  return mounted;
}

export default mountRoutes;
