// Standard API envelope helpers + the ApiError class.
// Success: { success:true, data, meta? }  Error: { success:false, error:{code,message,details} }

/**
 * Application error carrying an HTTP status + machine code.
 * Codes map to docs/API.md: VALIDATION_ERROR(400), UNAUTHORIZED(401), FORBIDDEN(403),
 * NOT_FOUND(404), CONFLICT(409), RATE_LIMITED(429), PAYMENT_ERROR(402), INTERNAL(500).
 */
export class ApiError extends Error {
  constructor(status, code, message, details = undefined) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }

  static badRequest(message = 'Validation failed', details) {
    return new ApiError(400, 'VALIDATION_ERROR', message, details);
  }

  static unauthorized(message = 'Unauthorized') {
    return new ApiError(401, 'UNAUTHORIZED', message);
  }

  static forbidden(message = 'Forbidden') {
    return new ApiError(403, 'FORBIDDEN', message);
  }

  static notFound(message = 'Not found') {
    return new ApiError(404, 'NOT_FOUND', message);
  }

  static conflict(message = 'Conflict') {
    return new ApiError(409, 'CONFLICT', message);
  }

  static rateLimited(message = 'Too many requests') {
    return new ApiError(429, 'RATE_LIMITED', message);
  }

  static payment(message = 'Payment error', details) {
    return new ApiError(402, 'PAYMENT_ERROR', message, details);
  }

  static internal(message = 'Internal server error') {
    return new ApiError(500, 'INTERNAL', message);
  }
}

/** Send a success response (200) with optional pagination meta. */
export function ok(res, data, meta) {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return res.status(200).json(body);
}

/** Send a created response (201). */
export function created(res, data, meta) {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return res.status(201).json(body);
}

export default { ok, created, ApiError };
