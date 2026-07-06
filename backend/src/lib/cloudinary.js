// Cloudinary image storage (used for category icons). The SDK auto-reads
// CLOUDINARY_URL from the environment; we call cloudinary.config() explicitly so
// it picks that up. Separate from R2 (which stays as-is for app/profile media).
import { v2 as cloudinary } from 'cloudinary';
import { config } from '../config/index.js';
import { ApiError } from '../utils/apiResponse.js';

// Picks up CLOUDINARY_URL from process.env.
cloudinary.config();

const PLACEHOLDER = '<your_api_key>';

/**
 * True only when CLOUDINARY_URL is set and is not the .env placeholder value.
 * @returns {boolean}
 */
export function isConfigured() {
  const url = config.cloudinary.url;
  return Boolean(url) && !url.includes(PLACEHOLDER);
}

/**
 * Upload an image buffer to Cloudinary via upload_stream.
 * @param {{buffer:Buffer, folder:string, publicId:string}} args
 * @returns {Promise<string>} the secure_url of the uploaded image
 */
export async function uploadImageBuffer({ buffer, folder, publicId }) {
  if (!isConfigured()) {
    throw ApiError.internal('Cloudinary is not configured — set CLOUDINARY_URL');
  }

  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      { folder, public_id: publicId, overwrite: true, resource_type: 'image' },
      (err, result) => {
        if (err) return reject(err);
        return resolve(result.secure_url);
      },
    );
    stream.end(buffer);
  });
}

export default { isConfigured, uploadImageBuffer };
