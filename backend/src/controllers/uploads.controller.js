// Thin HTTP handlers for the uploads (R2 presigned PUT) domain.
import { nanoid } from 'nanoid';
import path from 'path';
import { asyncHandler } from '../utils/asyncHandler.js';
import { created } from '../utils/apiResponse.js';
import { presignPut } from '../lib/r2.js';

// Map content types to a canonical extension when the filename lacks one.
const EXT_BY_TYPE = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/heic': '.heic',
  'image/heif': '.heif',
  'application/pdf': '.pdf',
};

/** Sanitize a filename to a safe slug, preserving its extension. */
function safeName(fileName, contentType) {
  const ext = (path.extname(fileName) || EXT_BY_TYPE[contentType] || '').toLowerCase();
  const base = path
    .basename(fileName, path.extname(fileName))
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48) || 'file';
  return `${base}${ext}`;
}

/**
 * POST /uploads/presign
 * Returns a short-lived R2 PUT URL. The object key is namespaced by userId + folder
 * so a user can never overwrite another user's media:
 *   uploads/<folder>/<userId>/<timestamp>-<nanoid>-<safeName>
 */
export const presign = asyncHandler(async (req, res) => {
  const { fileName, contentType, folder } = req.body;
  const userId = req.user.id;

  const key = `uploads/${folder}/${userId}/${Date.now()}-${nanoid(10)}-${safeName(
    fileName,
    contentType,
  )}`;

  const result = await presignPut({ key, contentType });
  return created(res, result);
});

export default { presign };
