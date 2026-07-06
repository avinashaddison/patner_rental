// Thin HTTP handlers for the payments domain.
import { ok, created } from '../utils/apiResponse.js';
import {
  createOrderForBooking,
  verifyAndCapture,
  handleWebhook,
  getPaymentForBooking,
  createUpiOrderForBooking,
  verifyUpiAndCapture,
  handleUpiWebhook,
  createQrOrderForBooking,
  verifyQrPayment,
  checkQrByUtr,
} from '../services/payments.service.js';

/** POST /payments/order */
export async function postOrder(req, res) {
  const { bookingId } = req.body;
  const order = await createOrderForBooking(bookingId, req.user.id);
  return created(res, order);
}

/** POST /payments/verify */
export async function postVerify(req, res) {
  const result = await verifyAndCapture(req.body, req.user.id);
  return ok(res, {
    bookingId: result.booking.id,
    bookingStatus: result.booking.status,
    paymentStatus: result.payment.status,
    payment: {
      id: result.payment.id,
      status: result.payment.status,
      razorpayPaymentId: result.payment.razorpayPaymentId,
      capturedAt: result.payment.capturedAt,
    },
  });
}

/**
 * POST /payments/webhook — raw body provided by express.raw in app.js.
 * Always returns 200 on a handled/ignored event so Razorpay does not retry valid ones;
 * a thrown ApiError (e.g. bad signature) flows to the error handler with its status.
 */
export async function postWebhook(req, res) {
  const signature = req.headers['x-razorpay-signature'];
  const result = await handleWebhook(req.body, signature);
  return ok(res, { received: true, ...result });
}

/** GET /payments/:bookingId */
export async function getByBooking(req, res) {
  const payment = await getPaymentForBooking(req.params.bookingId, req.user);
  return ok(res, payment);
}

/** POST /payments/upi/order — create a UPIGateway order, returns the hosted payment URL. */
export async function postUpiOrder(req, res) {
  const order = await createUpiOrderForBooking(req.body.bookingId, req.user.id);
  return created(res, order);
}

/** POST /payments/upi/verify — poll the gateway and capture when paid (idempotent). */
export async function postUpiVerify(req, res) {
  const result = await verifyUpiAndCapture(req.body.clientTxnId, req.user.id);
  return ok(res, result);
}

/**
 * POST /payments/upi/webhook — UNSIGNED urlencoded post from UPIGateway.
 * The service re-verifies against check_order_status; the body is never trusted.
 * Always 200 so the gateway does not hammer retries.
 */
export async function postUpiWebhook(req, res) {
  const result = await handleUpiWebhook(req.body);
  return ok(res, { received: true, ...result });
}

/**
 * GET /payments/upi/redirect — landing page the gateway sends the browser to
 * after payment. The app itself confirms via /payments/upi/verify polling.
 */
export async function getUpiRedirect(_req, res) {
  res
    .status(200)
    .type('html')
    .send(
      '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">' +
        '<title>Companion Ranchi</title></head>' +
        '<body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#faf7ff">' +
        '<div style="text-align:center;padding:24px"><h2 style="color:#6d28d9;margin:0 0 8px">Payment received</h2>' +
        '<p style="color:#475569;margin:0">You can close this window and return to the Companion Ranchi app.</p></div>' +
        '</body></html>',
    );
}

/** POST /payments/qr/order — self-hosted UPI QR (paise-tagged amount + intent). */
export async function postQrOrder(req, res) {
  const order = await createQrOrderForBooking(req.body.bookingId, req.user.id);
  return created(res, order);
}

/** POST /payments/qr/verify — poll a QR payment (captured by the mail watcher). */
export async function postQrVerify(req, res) {
  const result = await verifyQrPayment(req.body.ref, req.user.id);
  return ok(res, result);
}

/** POST /payments/qr/check-utr — confirm a QR payment by a manually entered UTR. */
export async function postQrCheckUtr(req, res) {
  const result = await checkQrByUtr(req.body.ref, req.body.utr, req.user.id);
  return ok(res, result);
}

export default {
  postOrder,
  postVerify,
  postWebhook,
  getByBooking,
  postUpiOrder,
  postUpiVerify,
  postUpiWebhook,
  getUpiRedirect,
  postQrOrder,
  postQrVerify,
  postQrCheckUtr,
};
