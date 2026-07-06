// Minimal structured logger. Zero-dependency; prints level-tagged lines with
// ISO timestamps. Use logger.info/warn/error/debug everywhere instead of console.
import { config } from '../config/index.js';

const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const activeLevel = config.isProd ? LEVELS.info : LEVELS.debug;

function emit(level, args) {
  if (LEVELS[level] > activeLevel) return;
  const ts = new Date().toISOString();
  const prefix = `[${ts}] [${level.toUpperCase()}]`;
  const fn = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log;
  fn(prefix, ...args);
}

export const logger = {
  error: (...args) => emit('error', args),
  warn: (...args) => emit('warn', args),
  info: (...args) => emit('info', args),
  debug: (...args) => emit('debug', args),
  // morgan stream adapter
  stream: {
    write: (message) => emit('info', [message.trim()]),
  },
};

export default logger;
