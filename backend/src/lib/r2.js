// Cloudflare R2 (S3-compatible) media storage.
// presignPut() returns a short-lived PUT URL plus the eventual public URL.
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config/index.js';
import { ApiError } from '../utils/apiResponse.js';

let s3 = null;

/**
 * Whether R2 is fully configured with REAL values (not the .env placeholders).
 * Rejects empty creds and any value still containing the `<...>` placeholder so
 * a half-filled .env fails loudly instead of producing a malformed upload URL
 * (which the mobile client surfaces as a cryptic "invalid url").
 */
export function isConfigured() {
  const { accessKeyId, secretAccessKey, endpoint, publicBaseUrl, bucket } = config.r2;
  const filled = (v) => Boolean(v) && !String(v).includes('<');
  return (
    filled(accessKeyId) &&
    filled(secretAccessKey) &&
    filled(endpoint) &&
    filled(publicBaseUrl) &&
    filled(bucket)
  );
}

/** Throw a clear, actionable error when storage isn't ready. */
function assertConfigured() {
  if (!isConfigured()) {
    throw new ApiError(
      503,
      'STORAGE_UNCONFIGURED',
      'Media storage (R2) is not configured. Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, ' +
        'R2_SECRET_ACCESS_KEY, R2_ENDPOINT and R2_PUBLIC_BASE_URL in the backend .env, then restart the server.',
    );
  }
}

function getClient() {
  if (!s3) {
    s3 = new S3Client({
      region: 'auto',
      endpoint: config.r2.endpoint || undefined,
      credentials: {
        accessKeyId: config.r2.accessKeyId,
        secretAccessKey: config.r2.secretAccessKey,
      },
      forcePathStyle: true,
    });
  }
  return s3;
}

/** Build the public URL for a stored object key. */
export function publicUrl(key) {
  const base = config.r2.publicBaseUrl.replace(/\/+$/, '');
  const cleanKey = String(key).replace(/^\/+/, '');
  return `${base}/${cleanKey}`;
}

/**
 * Generate a presigned PUT URL for direct browser/app upload to R2.
 * @param {{key:string, contentType:string, expiresIn?:number}} args
 * @returns {Promise<{uploadUrl:string, publicUrl:string, key:string}>}
 */
export async function presignPut({ key, contentType, expiresIn = 900 }) {
  assertConfigured();
  const command = new PutObjectCommand({
    Bucket: config.r2.bucket,
    Key: key,
    ContentType: contentType,
  });
  const uploadUrl = await getSignedUrl(getClient(), command, { expiresIn });
  return {
    uploadUrl,
    publicUrl: publicUrl(key),
    key,
  };
}

/** Pick a file extension from the content type, falling back to magic bytes. */
function imageExt(buffer, contentType) {
  const byType = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/heic': 'heic',
  }[String(contentType || '').toLowerCase()];
  if (byType) return byType;
  if (buffer && buffer.length > 12) {
    if (buffer[0] === 0xff && buffer[1] === 0xd8) return 'jpg';
    if (buffer[0] === 0x89 && buffer[1] === 0x50) return 'png';
    if (buffer.toString('ascii', 8, 12) === 'WEBP') return 'webp';
    if (buffer[0] === 0x47 && buffer[1] === 0x49) return 'gif';
  }
  return 'jpg';
}

/**
 * Server-side upload of a buffer to R2 (used by admin uploads that stream through
 * the backend, unlike the app which PUTs directly via a presigned URL).
 * @param {{key:string, buffer:Buffer, contentType?:string}} args
 * @returns {Promise<string>} the public URL of the stored object
 */
export async function uploadBuffer({ key, buffer, contentType }) {
  assertConfigured();
  await getClient().send(
    new PutObjectCommand({
      Bucket: config.r2.bucket,
      Key: key,
      Body: buffer,
      ContentType: contentType || 'application/octet-stream',
    }),
  );
  return publicUrl(key);
}

/**
 * Upload an image buffer and return its public URL. Drop-in replacement for the
 * former external image helper: `{ buffer, folder, publicId, contentType? }`. A short
 * timestamp is appended to the key so each upload gets a fresh (cache-busting)
 * URL rather than overwriting the CDN-cached object.
 * @returns {Promise<string>}
 */
export async function uploadImageBuffer({ buffer, folder, publicId, contentType }) {
  const ext = imageExt(buffer, contentType);
  const cleanFolder = String(folder || 'uploads').replace(/^\/+|\/+$/g, '');
  const key = `${cleanFolder}/${publicId}-${Date.now().toString(36)}.${ext}`;
  const type = contentType || `image/${ext === 'jpg' ? 'jpeg' : ext}`;
  return uploadBuffer({ key, buffer, contentType: type });
}

export default { presignPut, publicUrl, isConfigured, uploadBuffer, uploadImageBuffer };
