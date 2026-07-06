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

export default { presignPut, publicUrl, isConfigured };
