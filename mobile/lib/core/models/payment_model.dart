import 'package:companion_ranchi/core/models/json_utils.dart';

/// A payment (payments table). Also carries the Razorpay order fields needed
/// by the checkout sheet (`POST /payments/order` returns `razorpayOrderId,
/// amount, currency, keyId`).
class PaymentModel {
  const PaymentModel({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.currency,
    required this.status,
    this.customerId,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.razorpaySignature,
    this.keyId,
    this.method = 'razorpay',
    this.capturedAt,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String? customerId;

  final double amount;
  final String currency;

  /// `CREATED` | `AUTHORIZED` | `CAPTURED` | `FAILED` | `REFUNDED`.
  final String status;

  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? razorpaySignature;

  /// Razorpay public key id (only present on order creation response).
  final String? keyId;
  final String method;
  final DateTime? capturedAt;
  final DateTime? createdAt;

  bool get isCaptured => status == 'CAPTURED';
  bool get isRefunded => status == 'REFUNDED';
  bool get isFailed => status == 'FAILED';
  bool get isPending => status == 'CREATED' || status == 'AUTHORIZED';

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: J.asString(json['id']),
        bookingId: J.asString(json['bookingId']),
        customerId: J.asStringOrNull(json['customerId']),
        amount: J.asDouble(json['amount']),
        currency: J.asString(json['currency'], 'INR'),
        status: J.asString(json['status'], 'CREATED'),
        razorpayOrderId: J.asStringOrNull(json['razorpayOrderId']),
        razorpayPaymentId: J.asStringOrNull(json['razorpayPaymentId']),
        razorpaySignature: J.asStringOrNull(json['razorpaySignature']),
        keyId: J.asStringOrNull(json['keyId']),
        method: J.asString(json['method'], 'razorpay'),
        capturedAt: J.asDate(json['capturedAt']),
        createdAt: J.asDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'customerId': customerId,
        'amount': amount,
        'currency': currency,
        'status': status,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
        'keyId': keyId,
        'method': method,
        'capturedAt': capturedAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
      };
}
