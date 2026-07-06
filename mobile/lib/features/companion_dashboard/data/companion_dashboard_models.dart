import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/transaction_model.dart';

/// Aggregated stats for the companion dashboard header cards.
/// Returned by `GET /companion/dashboard` (API.md §7):
/// ```json
/// { "totalEarnings", "pendingEarnings", "withdrawnEarnings",
///   "upcomingBookings", "ratingAvg", "ratingCount", "reviewCount" }
/// ```
class CompanionDashboard {
  const CompanionDashboard({
    required this.totalEarnings,
    required this.pendingEarnings,
    required this.withdrawnEarnings,
    required this.upcomingBookings,
    required this.ratingAvg,
    required this.ratingCount,
    required this.reviewCount,
  });

  /// Lifetime gross earnings credited to the wallet.
  final double totalEarnings;

  /// Earnings not yet released (bookings not completed / payouts pending).
  final double pendingEarnings;

  /// Total amount already withdrawn via payouts.
  final double withdrawnEarnings;

  /// Count of upcoming (confirmed / pending) bookings.
  final int upcomingBookings;

  final double ratingAvg;
  final int ratingCount;
  final int reviewCount;

  factory CompanionDashboard.fromJson(Map<String, dynamic> json) =>
      CompanionDashboard(
        totalEarnings: J.asDouble(json['totalEarnings']),
        pendingEarnings: J.asDouble(json['pendingEarnings']),
        withdrawnEarnings: J.asDouble(json['withdrawnEarnings']),
        upcomingBookings: J.asInt(json['upcomingBookings']),
        ratingAvg: J.asDouble(json['ratingAvg']),
        ratingCount: J.asInt(json['ratingCount']),
        reviewCount: J.asInt(json['reviewCount']),
      );

  static const empty = CompanionDashboard(
    totalEarnings: 0,
    pendingEarnings: 0,
    withdrawnEarnings: 0,
    upcomingBookings: 0,
    ratingAvg: 0,
    ratingCount: 0,
    reviewCount: 0,
  );
}

/// Earnings breakdown + recent ledger entries from `GET /companion/earnings`.
class CompanionEarnings {
  const CompanionEarnings({
    required this.totalEarnings,
    required this.pendingEarnings,
    required this.withdrawnEarnings,
    required this.availableBalance,
    required this.commissionPaid,
    required this.transactions,
  });

  final double totalEarnings;
  final double pendingEarnings;
  final double withdrawnEarnings;

  /// Withdrawable wallet balance.
  final double availableBalance;

  /// Total platform commission deducted across all bookings.
  final double commissionPaid;

  /// Recent wallet transactions (most recent first).
  final List<TransactionModel> transactions;

  factory CompanionEarnings.fromJson(Map<String, dynamic> json) {
    return CompanionEarnings(
      totalEarnings: J.asDouble(json['totalEarnings']),
      pendingEarnings: J.asDouble(json['pendingEarnings']),
      withdrawnEarnings: J.asDouble(json['withdrawnEarnings']),
      availableBalance:
          J.asDouble(json['availableBalance'] ?? json['balance']),
      commissionPaid: J.asDouble(json['commissionPaid']),
      transactions: J
          .asMapList(json['transactions'] ?? json['recentTransactions'])
          .map(TransactionModel.fromJson)
          .toList(growable: false),
    );
  }

  static const empty = CompanionEarnings(
    totalEarnings: 0,
    pendingEarnings: 0,
    withdrawnEarnings: 0,
    availableBalance: 0,
    commissionPaid: 0,
    transactions: [],
  );
}
