import 'package:companion_ranchi/core/models/json_utils.dart';

/// An immutable wallet ledger entry (transactions table). Returned by
/// `GET /wallet/transactions`.
class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.status,
    this.walletId,
    this.userId,
    this.bookingId,
    this.reference,
    this.description,
    this.createdAt,
  });

  final String id;
  final String? walletId;
  final String? userId;
  final String? bookingId;

  /// `CREDIT` | `DEBIT` | `PAYOUT` | `REFUND` | `COMMISSION` |
  /// `REFERRAL_REWARD` | `BOOKING_EARNING`.
  final String type;

  /// Signed by type (credits positive, debits negative).
  final double amount;
  final double balanceAfter;

  /// `PENDING` | `COMPLETED` | `FAILED`.
  final String status;
  final String? reference;
  final String? description;
  final DateTime? createdAt;

  bool get isCredit => amount >= 0;

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: J.asString(json['id']),
        walletId: J.asStringOrNull(json['walletId']),
        userId: J.asStringOrNull(json['userId']),
        bookingId: J.asStringOrNull(json['bookingId']),
        type: J.asString(json['type']),
        amount: J.asDouble(json['amount']),
        balanceAfter: J.asDouble(json['balanceAfter']),
        status: J.asString(json['status'], 'COMPLETED'),
        reference: J.asStringOrNull(json['reference']),
        description: J.asStringOrNull(json['description']),
        createdAt: J.asDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'walletId': walletId,
        'userId': userId,
        'bookingId': bookingId,
        'type': type,
        'amount': amount,
        'balanceAfter': balanceAfter,
        'status': status,
        'reference': reference,
        'description': description,
        'createdAt': createdAt?.toIso8601String(),
      };

  static String typeLabel(String type) {
    switch (type) {
      case 'CREDIT':
        return 'Credit';
      case 'DEBIT':
        return 'Debit';
      case 'PAYOUT':
        return 'Payout';
      case 'REFUND':
        return 'Refund';
      case 'COMMISSION':
        return 'Commission';
      case 'REFERRAL_REWARD':
        return 'Referral Reward';
      case 'BOOKING_EARNING':
        return 'Booking Earning';
      default:
        return type;
    }
  }
}
