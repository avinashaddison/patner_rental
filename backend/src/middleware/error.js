// Central error handler + 404 handler. Normalizes errors to the API envelope.
import { ZodError } from 'zod';
import { ApiError } from '../utils/apiResponse.js';
import { logger } from '../lib/logger.js';

/** 404 for unmatched routes. */
export function notFound(req, _res, next) {
  next(new ApiError(404, 'NOT_FOUND', `Route not found: ${req.method} ${req.originalUrl}`));
}

// Map Prisma error codes to API errors.
function fromPrisma(err) {
  switch (err.code) {
    case 'P2002':
      return new ApiError(409, 'CONFLICT', `Duplicate value for ${(err.meta?.target || []).join(', ') || 'unique field'}`);
    case 'P2025':
      return new ApiError(404, 'NOT_FOUND', 'Record not found');
    case 'P2003':
      return new ApiError(400, 'VALIDATION_ERROR', 'Related record does not exist');
    default:
      return null;
  }
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  let apiError;

  if (err instanceof ApiError) {
    apiError = err;
  } else if (err instanceof ZodError) {
    apiError = ApiError.badRequest(
      'Validation failed',
      err.errors.map((e) => ({ path: e.path.join('.'), message: e.message })),
    );
  } else if (err?.code && typeof err.code === 'string' && err.code.startsWith('P')) {
    apiError = fromPrisma(err) || ApiError.internal();
  } else if (err?.type === 'entity.parse.failed') {
    apiError = ApiError.badRequest('Malformed JSON body');
  } else {
    apiError = ApiError.internal(err?.message || 'Internal server error');
  }

  if (apiError.status >= 500) {
    logger.error(`${req.method} ${req.originalUrl} -> ${apiError.status}`, err?.stack || err);
  } else {
    logger.debug(`${req.method} ${req.originalUrl} -> ${apiError.status} ${apiError.code}`);
  }

  res.status(apiError.status).json({
    success: false,
    error: {
      code: apiError.code,
      message: apiError.message,
      details: apiError.details ?? [],
    },
  });
}

export default { errorHandler, notFound };
