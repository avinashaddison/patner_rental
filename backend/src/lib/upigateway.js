// UPIGateway (ekqr.in) API client — UPI QR/intent payments.
// Docs: https://api.ekqr.in  (create_order + check_order_status; webhook is an
// UNSIGNED x-www-form-urlencoded POST, so callers MUST re-verify every webhook
// via checkOrderStatus() before trusting it).
import dayjs from 'dayjs';
import { config } from '../config/index.js';
import { logger } from './logger.js';

const BASE_URL = 'https://api.ekqr.in/api';

export function isUpiGatewayConfigured() {
  return Boolean(config.upigateway.key);
}

async function post(path, body) {
  const res = await fetch(`${BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });

  let json = null;
  try {
    json = await res.json();
  } catch {
    // fall through — treated as gateway error below
  }

  if (!res.ok || !json || json.status !== true) {
    const msg = json?.msg || `UPIGateway request failed (${res.status})`;
    const err = new Error(msg);
    err.gateway = json;
    throw err;
  }
  return json;
}

/**
 * Create a UPI payment order.
 * @returns {{orderId:number, paymentUrl:string, upiIdHash?:string, upiIntent?:object}}
 */
export async function createUpiOrder({
  clientTxnId,
  amount,
  productInfo,
  customerName,
  customerEmail,
  customerMobile,
  redirectUrl,
  udf1,
  udf2,
  udf3,
}) {
  const json = await post('/create_order', {
    key: config.upigateway.key,
    client_txn_id: clientTxnId,
    // Gateway expects a whole-rupee string amount.
    amount: String(Math.round(Number(amount))),
    p_info: productInfo,
    customer_name: customerName,
    customer_email: customerEmail,
    customer_mobile: customerMobile,
    redirect_url: redirectUrl,
    ...(udf1 ? { udf1 } : {}),
    ...(udf2 ? { udf2 } : {}),
    ...(udf3 ? { udf3 } : {}),
  });

  return {
    orderId: json.data?.order_id,
    paymentUrl: json.data?.payment_url,
    upiIdHash: json.data?.upi_id_hash,
    upiIntent: json.data?.upi_intent,
  };
}

/**
 * Check the real status of an order at the gateway (source of truth).
 * Rate limited to 500 req/min by the gateway.
 * @param {string} clientTxnId  client_txn_id used at create time
 * @param {Date|string} txnDate  the date the order was CREATED (gateway wants DD-MM-YYYY)
 * @returns {{found:boolean, status?:'created'|'success'|'failure', amount?:number,
 *            upiTxnId?:string, remark?:string, customerVpa?:string, raw?:object}}
 */
export async function checkUpiOrderStatus(clientTxnId, txnDate) {
  try {
    const json = await post('/check_order_status', {
      key: config.upigateway.key,
      client_txn_id: clientTxnId,
      txn_date: dayjs(txnDate).format('DD-MM-YYYY'),
    });
    const d = json.data || {};
    return {
      found: true,
      status: d.status,
      amount: Number(d.amount),
      upiTxnId: d.upi_txn_id || null,
      remark: d.remark || null,
      customerVpa: d.customer_vpa || null,
      raw: d,
    };
  } catch (err) {
    // "Transaction not found" style responses land here — report as not found.
    logger.debug(`[upigateway] status check failed for ${clientTxnId}: ${err.message}`);
    return { found: false };
  }
}

export default { isUpiGatewayConfigured, createUpiOrder, checkUpiOrderStatus };
