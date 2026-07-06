import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/payment_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// Result of `POST /payments/order` — the data needed to open the Razorpay
/// checkout sheet (`razorpayOrderId, amount, currency, keyId`).
class RazorpayOrder {
  const RazorpayOrder({
    required this.razorpayOrderId,
    required this.amount,
    required this.currency,
    required this.keyId,
  });

  final String razorpayOrderId;

  /// Amount in INR (rupees) as returned by the API. Razorpay's SDK expects the
  /// amount in **paise**, so the checkout layer multiplies by 100.
  final double amount;
  final String currency;
  final String keyId;

  /// Amount in the smallest currency unit (paise) for the Razorpay SDK.
  int get amountInPaise => (amount * 100).round();

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) => RazorpayOrder(
        razorpayOrderId: J.asString(json['razorpayOrderId']),
        amount: J.asDouble(json['amount']),
        currency: J.asString(json['currency'], 'INR'),
        keyId: J.asString(json['keyId']),
      );
}

/// Result of `POST /payments/upi/order` — hosted UPI payment page (UPIGateway)
/// for a booking. The app opens [paymentUrl] and then polls `verifyUpi`.
class UpiOrder {
  const UpiOrder({
    required this.clientTxnId,
    required this.paymentUrl,
    required this.amount,
    required this.currency,
  });

  final String clientTxnId;
  final String paymentUrl;
  final double amount;
  final String currency;

  factory UpiOrder.fromJson(Map<String, dynamic> json) => UpiOrder(
        clientTxnId: J.asString(json['clientTxnId']),
        paymentUrl: J.asString(json['paymentUrl']),
        amount: J.asDouble(json['amount']),
        currency: J.asString(json['currency'], 'INR'),
      );
}

/// Result of `POST /payments/upi/verify` — a single gateway status poll.
class UpiVerifyResult {
  const UpiVerifyResult({
    required this.bookingStatus,
    required this.paymentStatus,
    required this.gatewayStatus,
  });

  /// Booking status after the check (CONFIRMED once paid).
  final String bookingStatus;

  /// Our payment row status: CREATED / CAPTURED / FAILED.
  final String paymentStatus;

  /// Raw gateway state: created / scanning / success / failure / pending…
  final String gatewayStatus;

  bool get isPaid => paymentStatus == 'CAPTURED';
  bool get isFailed => paymentStatus == 'FAILED' || gatewayStatus == 'failure';

  factory UpiVerifyResult.fromJson(Map<String, dynamic> json) =>
      UpiVerifyResult(
        bookingStatus: J.asString(json['bookingStatus']),
        paymentStatus: J.asString(json['paymentStatus']),
        gatewayStatus: J.asString(json['gatewayStatus']),
      );
}

/// Result of `POST /payments/qr/order` — a self-hosted dynamic UPI QR.
/// The EXACT paise-tagged [amount] is how the bank credit is matched back to
/// this order, so the UI must tell the user to pay exactly that amount
/// (the QR/intent already carry it).
class QrOrder {
  const QrOrder({
    required this.ref,
    required this.upiIntent,
    required this.vpa,
    required this.payeeName,
    required this.amount,
    this.expiresAt,
  });

  final String ref;

  /// `upi://pay?...` payload — rendered as the QR and used for the intent button.
  final String upiIntent;
  final String vpa;
  final String payeeName;
  final double amount;
  final DateTime? expiresAt;

  factory QrOrder.fromJson(Map<String, dynamic> json) => QrOrder(
        ref: J.asString(json['ref']),
        upiIntent: J.asString(json['upiIntent']),
        vpa: J.asString(json['vpa']),
        payeeName: J.asString(json['payeeName']),
        amount: J.asDouble(json['amount']),
        expiresAt: json['expiresAt'] != null
            ? DateTime.tryParse(J.asString(json['expiresAt']))
            : null,
      );
}

/// Data access for the payment + Razorpay verification flow (`/payments`).
class PaymentRepository {
  PaymentRepository(this._api);

  final ApiClient _api;

  /// `POST /payments/order` — provision (or reuse) a Razorpay order for a
  /// pending booking. Returns the order + public key id for checkout.
  Future<RazorpayOrder> createOrder(String bookingId) async {
    final data = await _api.postJson(
      '/payments/order',
      body: {'bookingId': bookingId},
    );
    return RazorpayOrder.fromJson(J.asMap(data));
  }

  /// `POST /payments/verify` — verify the Razorpay signature server-side. On
  /// success the backend captures the payment and confirms the booking; the
  /// confirmed [BookingModel] is returned so the UI can show the booking code.
  Future<BookingModel> verify({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final data = await _api.postJson(
      '/payments/verify',
      body: {
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
    );
    final map = J.asMap(data);
    final bookingJson =
        map['booking'] is Map ? J.asMap(map['booking']) : map;
    return BookingModel.fromJson(bookingJson);
  }

  /// `GET /payments/:bookingId` — current payment status for a booking.
  Future<PaymentModel> getByBooking(String bookingId) async {
    final data = await _api.getJson('/payments/$bookingId');
    return PaymentModel.fromJson(J.asMap(data));
  }

  /// `POST /payments/upi/order` — provision a UPIGateway order and get the
  /// hosted payment URL to open in the browser / UPI app.
  Future<UpiOrder> createUpiOrder(String bookingId) async {
    final data = await _api.postJson(
      '/payments/upi/order',
      body: {'bookingId': bookingId},
    );
    return UpiOrder.fromJson(J.asMap(data));
  }

  /// `POST /payments/upi/verify` — ask the backend to check the gateway and
  /// capture when paid. Safe to call repeatedly (idempotent server-side).
  Future<UpiVerifyResult> verifyUpi(String clientTxnId) async {
    final data = await _api.postJson(
      '/payments/upi/verify',
      body: {'clientTxnId': clientTxnId},
    );
    return UpiVerifyResult.fromJson(J.asMap(data));
  }

  /// `POST /payments/qr/order` — create a self-hosted UPI QR for a booking.
  Future<QrOrder> createQrOrder(String bookingId) async {
    final data = await _api.postJson(
      '/payments/qr/order',
      body: {'bookingId': bookingId},
    );
    return QrOrder.fromJson(J.asMap(data));
  }

  /// `POST /payments/qr/verify` — poll a QR payment (captured server-side when
  /// the bank's credit-alert email arrives). Same result shape as [verifyUpi].
  Future<UpiVerifyResult> verifyQr(String ref) async {
    final data = await _api.postJson(
      '/payments/qr/verify',
      body: {'ref': ref},
    );
    return UpiVerifyResult.fromJson(J.asMap(data));
  }

  /// `POST /payments/qr/check-utr` — manual fallback: confirm a QR payment by
  /// the UTR the customer copied from their UPI app. Returns a `result` string:
  /// captured | already | not_found | duplicate_utr | amount_short.
  Future<UtrCheckResult> checkQrByUtr(String ref, String utr) async {
    final data = await _api.postJson(
      '/payments/qr/check-utr',
      body: {'ref': ref, 'utr': utr},
    );
    return UtrCheckResult.fromJson(J.asMap(data));
  }
}

/// Result of a manual UTR check (`POST /payments/qr/check-utr`).
class UtrCheckResult {
  const UtrCheckResult({required this.paymentStatus, required this.result});

  final String paymentStatus;

  /// captured | already | not_found | duplicate_utr | amount_short
  final String result;

  bool get isPaid =>
      paymentStatus == 'CAPTURED' || result == 'captured' || result == 'already';

  /// A user-facing message for the non-paid outcomes.
  String get message {
    switch (result) {
      case 'not_found':
        return 'We haven\'t received this payment yet. If you just paid, wait a '
            'few seconds and try again — the bank confirmation can take a minute.';
      case 'duplicate_utr':
        return 'This UTR has already been used for another payment.';
      case 'amount_mismatch':
        return 'This UTR is for a different amount. Please pay the exact amount '
            'shown for this booking, or contact support.';
      case 'expired':
        return 'This QR has expired. Please go back and start the payment again '
            'for a fresh QR.';
      default:
        return 'Payment not confirmed yet. Please try again shortly.';
    }
  }

  factory UtrCheckResult.fromJson(Map<String, dynamic> json) => UtrCheckResult(
        paymentStatus: J.asString(json['paymentStatus']),
        result: J.asString(json['result']),
      );
}

/// Provider for [PaymentRepository].
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(apiClientProvider));
});
