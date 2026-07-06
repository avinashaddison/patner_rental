// Zod validation middleware. Validates and *replaces* the chosen request source
// with the parsed (coerced) value, so controllers receive clean typed data.
import { ZodError } from 'zod';
import { ApiError } from '../utils/apiResponse.js';

/**
 * @param {import('zod').ZodTypeAny} schema
 * @param {'body'|'query'|'params'} source
 */
export function validate(schema, source = 'body') {
  return (req, _res, next) => {
    try {
      const parsed = schema.parse(req[source]);
      req[source] = parsed;
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        const details = err.errors.map((e) => ({
          path: e.path.join('.'),
          message: e.message,
        }));
        return next(ApiError.badRequest('Validation failed', details));
      }
      return next(err);
    }
  };
}

export default validate;
