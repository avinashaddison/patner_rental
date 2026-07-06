// Thin HTTP handlers for the wallet + payouts domain.
import { ok, created } from '../utils/apiResponse.js';
import {
  getWalletSummary,
  listTransactions,
  requestPayout,
  listPayouts,
} from '../services/wallet.service.js';

/** GET /wallet */
export async function getWallet(req, res) {
  const wallet = await getWalletSummary(req.user.id);
  return ok(res, wallet);
}

/** GET /wallet/transactions */
export async function getTransactions(req, res) {
  const { data, meta } = await listTransactions(req, req.user.id);
  return ok(res, data, meta);
}

/** POST /wallet/payouts */
export async function postPayout(req, res) {
  const payout = await requestPayout(req.user.id, req.body);
  return created(res, payout);
}

/** GET /wallet/payouts */
export async function getPayouts(req, res) {
  const { data, meta } = await listPayouts(req, req.user.id);
  return ok(res, data, meta);
}

export default { getWallet, getTransactions, postPayout, getPayouts };
