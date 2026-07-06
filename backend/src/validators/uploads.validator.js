// Zod request schemas for the uploads (R2 presign) domain.
import { z } from 'zod';

// Folders the app uploads into. Keeps object keys namespaced + predictable.
export const UPLOAD_FOLDERS = [
  'profile',
  'companion-photos',
  'kyc',
  'chat',
  'reports',
  'posts',
  'misc',
];

// Restrict presign to image/document content types used by the app.
const ALLOWED_CONTENT_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
];

/** POST /uploads/presign. */
export const presignSchema = z.object({
  fileName: z.string().trim().min(1, 'fileName is required').max(255),
  contentType: z.enum(ALLOWED_CONTENT_TYPES, {
    errorMap: () => ({ message: 'Unsupported contentType' }),
  }),
  folder: z.enum(UPLOAD_FOLDERS, {
    errorMap: () => ({ message: 'Unsupported folder' }),
  }),
});

export default { presignSchema, UPLOAD_FOLDERS, ALLOWED_CONTENT_TYPES };
