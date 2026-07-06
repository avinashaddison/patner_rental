import 'package:companion_ranchi/core/models/json_utils.dart';

/// A user's wallet (wallet table). Companions accrue earnings here; customers
/// hold referral/refund credit. Returned by `GET /wallet`.
class WalletModel {
  const WalletModel({
    required this.balance,
    required this.pendingBalance,
    required this.totalEarned,
    required this.totalWithdrawn,
    this.currency = 'INR',
    this.id,
    this.userId,
  });

  final String? id;
  final String? userId;

  /// Available (withdrawable) balance.
  final double balance;

  /// Earnings not yet released (e.g. from bookings not completed).
  final double pendingBalance;
  final double totalEarned;
  final double totalWithdrawn;
  final String currency;

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        id: J.asStringOrNull(json['id']),
        userId: J.asStringOrNull(json['userId']),
        balance: J.asDouble(json['balance']),
        pendingBalance: J.asDouble(json['pendingBalance']),
        totalEarned: J.asDouble(json['totalEarned']),
        totalWithdrawn: J.asDouble(json['totalWithdrawn']),
        currency: J.asString(json['currency'], 'INR'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'balance': balance,
        'pendingBalance': pendingBalance,
        'totalEarned': totalEarned,
        'totalWithdrawn': totalWithdrawn,
        'currency': currency,
      };

  static const empty = WalletModel(
    balance: 0,
    pendingBalance: 0,
    totalEarned: 0,
    totalWithdrawn: 0,
  );
}
