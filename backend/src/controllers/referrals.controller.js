// Thin HTTP handlers for the referrals domain.
import { ok } from '../utils/apiResponse.js';
import { getMyReferrals, applyReferralCode } from '../services/referrals.service.js';

/** GET /referrals/me */
export async function getMine(req, res) {
  const data = await getMyReferrals(req.user.id);
  return ok(res, data);
}

/** POST /referrals/apply */
export async function postApply(req, res) {
  const data = await applyReferralCode(req.user.id, req.body.code);
  return ok(res, data);
}

export default { getMine, postApply };
