// Thin HTTP handlers for the KYC module.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import * as kycService from '../services/kyc.service.js';

export const submit = asyncHandler(async (req, res) => {
  const data = await kycService.submitKyc(req.user, req.body);
  return created(res, data);
});

export const status = asyncHandler(async (req, res) => {
  const data = await kycService.getStatus(req.user);
  return ok(res, data);
});

export default { submit, status };
