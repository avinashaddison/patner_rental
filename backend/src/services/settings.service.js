// Runtime key/value settings backed by the `settings` table (JSON values).
// getSetting falls back to a provided default (and ultimately to config) when absent.
import { prisma } from '../lib/prisma.js';
import { config } from '../config/index.js';

/**
 * Read a setting value by key.
 * @param {string} key
 * @param {*} fallback  returned when the key is not present
 */
// Settings change rarely but are read on hot paths (quote, booking, meta config,
// payment-method checks). Cache each key for a few seconds so a burst of reads
// costs one round-trip, not one per read. Invalidated on write.
const _settingCache = new Map(); // key -> { value, at(ms) }
const SETTING_TTL_MS = 15_000;

export async function getSetting(key, fallback = undefined) {
  const hit = _settingCache.get(key);
  if (hit && Date.now() - hit.at < SETTING_TTL_MS) {
    return hit.value === undefined ? fallback : hit.value;
  }
  const row = await prisma.setting.findUnique({ where: { key } });
  const value = row ? row.value : undefined;
  _settingCache.set(key, { value, at: Date.now() });
  return value === undefined ? fallback : value;
}

/**
 * Upsert a setting value.
 * @param {string} key
 * @param {*} value  any JSON-serializable value
 * @param {{description?:string, updatedById?:string}} [opts]
 */
export async function setSetting(key, value, opts = {}) {
  const row = await prisma.setting.upsert({
    where: { key },
    create: { key, value, description: opts.description, updatedById: opts.updatedById },
    update: { value, updatedById: opts.updatedById },
  });
  _settingCache.set(key, { value, at: Date.now() }); // keep cache fresh on write
  return row;
}

/** Convenience: current commission rate (percent), falling back to config default. */
export async function getCommissionRate() {
  const v = await getSetting('commission_rate', config.business.commissionRate);
  const n = Number(v);
  return Number.isFinite(n) ? n : config.business.commissionRate;
}

/** Convenience: referral reward amount (INR). */
export async function getReferralReward() {
  const v = await getSetting('referral_reward', config.business.referralReward);
  const n = Number(v);
  return Number.isFinite(n) ? n : config.business.referralReward;
}

/** Convenience: minimum payout amount (INR). */
export async function getMinPayout() {
  const v = await getSetting('min_payout', config.business.minPayout);
  const n = Number(v);
  return Number.isFinite(n) ? n : config.business.minPayout;
}

/**
 * Home-screen category icon size, admin-controlled via `home_category_icon_size`
 * (stored as a percentage 30–100). Returned to the app as a 0..1 fraction of the
 * tile the icon should fill. Defaults to 46%.
 */
export async function getCategoryIconScale() {
  const v = await getSetting('home_category_icon_size', 46);
  const n = Number(v);
  const pct = Number.isFinite(n) ? Math.min(100, Math.max(30, n)) : 46;
  return pct / 100;
}

/** Supported payment methods (identifiers stored on Payment.method). */
export const PAYMENT_METHODS = ['razorpay', 'upiqr', 'upigateway', 'cash'];

/**
 * UPI receiving details for self-hosted QR payments — admin-controlled via the
 * `upi_vpa` / `upi_payee_name` settings, falling back to UPIQR_* env config.
 */
export async function getUpiReceiving() {
  const [vpa, payeeName] = await Promise.all([
    getSetting('upi_vpa', config.upiqr.vpa),
    getSetting('upi_payee_name', config.upiqr.payeeName),
  ]);
  return {
    vpa: typeof vpa === 'string' ? vpa.trim() : '',
    payeeName:
      typeof payeeName === 'string' && payeeName.trim()
        ? payeeName.trim()
        : config.upiqr.payeeName,
  };
}

/**
 * Which payment methods are enabled (admin-controlled via the `payment_methods`
 * setting). Returns e.g. `{ razorpay: true, cash: true }`. A method is enabled
 * unless explicitly set to false; there is always at least one enabled method.
 */
export async function getEnabledPaymentMethods() {
  const raw = await getSetting('payment_methods', null);
  const result = {};
  for (const m of PAYMENT_METHODS) {
    result[m] = raw && typeof raw === 'object' ? raw[m] !== false : true;
  }
  // Self-hosted UPI QR is only OPERATIONAL when a receiving VPA is set — without
  // it a QR can't be generated and a paid customer could never be confirmed.
  if (result.upiqr) {
    const { vpa } = await getUpiReceiving();
    if (!vpa) result.upiqr = false;
  }
  if (!Object.values(result).some(Boolean)) result.razorpay = true; // never zero
  return result;
}

/** True when the given payment method is currently enabled. */
export async function isPaymentMethodEnabled(method) {
  const enabled = await getEnabledPaymentMethods();
  return Boolean(enabled[method]);
}

export default {
  getSetting,
  setSetting,
  getCommissionRate,
  getReferralReward,
  getMinPayout,
  getCategoryIconScale,
  getEnabledPaymentMethods,
  isPaymentMethodEnabled,
  getUpiReceiving,
  PAYMENT_METHODS,
};
