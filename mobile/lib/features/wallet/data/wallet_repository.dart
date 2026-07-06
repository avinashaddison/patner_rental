import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/transaction_model.dart';
import 'package:companion_ranchi/core/models/wallet_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// One page of the wallet ledger plus whether more (older) entries exist, for
/// infinite scroll. Backend returns newest-first (`sort=createdAt:desc`).
class TransactionPage {
  const TransactionPage({
    required this.transactions,
    required this.hasMore,
    required this.page,
  });

  final List<TransactionModel> transactions;
  final bool hasMore;
  final int page;
}

/// A submitted payout (withdrawal) request returned by `POST /wallet/payouts`
/// and listed by `GET /wallet/payouts`. Mirrors the `payouts` table.
class PayoutModel {
  const PayoutModel({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    this.upiId,
    this.bankAccountName,
    this.bankAccountNumber,
    this.ifsc,
    this.notes,
    this.createdAt,
    this.processedAt,
  });

  final String id;
  final double amount;

  /// `BANK_TRANSFER` | `UPI`.
  final String method;

  /// `REQUESTED` | `PROCESSING` | `COMPLETED` | `FAILED` | `REJECTED`.
  final String status;
  final String? upiId;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? ifsc;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? processedAt;

  factory PayoutModel.fromJson(Map<String, dynamic> json) => PayoutModel(
        id: J.asString(json['id']),
        amount: J.asDouble(json['amount']),
        method: J.asString(json['method'], 'UPI'),
        status: J.asString(json['status'], 'REQUESTED'),
        upiId: J.asStringOrNull(json['upiId']),
        bankAccountName: J.asStringOrNull(json['bankAccountName']),
        bankAccountNumber: J.asStringOrNull(json['bankAccountNumber']),
        ifsc: J.asStringOrNull(json['ifsc']),
        notes: J.asStringOrNull(json['notes']),
        createdAt: J.asDate(json['createdAt']),
        processedAt: J.asDate(json['processedAt']),
      );

  static String methodLabel(String method) =>
      method == 'BANK_TRANSFER' ? 'Bank Transfer' : 'UPI';

  static String statusLabel(String status) {
    switch (status) {
      case 'REQUESTED':
        return 'Requested';
      case 'PROCESSING':
        return 'Processing';
      case 'COMPLETED':
        return 'Completed';
      case 'FAILED':
        return 'Failed';
      case 'REJECTED':
        return 'Rejected';
      default:
        return status;
    }
  }
}

/// Data access for the wallet domain (`/wallet/*`). Talks to the endpoints in
/// API.md section 6 and maps responses into the shared [WalletModel] /
/// [TransactionModel] plus the local [PayoutModel].
class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;

  /// `GET /wallet` → balance / pendingBalance / totalEarned / totalWithdrawn.
  Future<WalletModel> fetchWallet() async {
    final data = await _api.getJson('/wallet');
    final map = J.asMap(data);
    // Tolerate an envelope that nests the wallet under `wallet`.
    final walletJson = map['wallet'] is Map ? J.asMap(map['wallet']) : map;
    return WalletModel.fromJson(walletJson);
  }

  /// `GET /wallet/transactions` → paginated immutable ledger (newest-first).
  Future<TransactionPage> fetchTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    final envelope = await _api.getEnvelope(
      '/wallet/transactions',
      query: {'page': page, 'limit': limit, 'sort': 'createdAt:desc'},
    );
    final transactions = _asTransactionList(envelope['data']);
    final hasMore = _hasMore(envelope['meta'], page, limit, transactions.length);
    return TransactionPage(
      transactions: transactions,
      hasMore: hasMore,
      page: page,
    );
  }

  /// `GET /wallet/payouts` → companion payout history.
  Future<List<PayoutModel>> fetchPayouts() async {
    final data = await _api.getJson('/wallet/payouts');
    final list = data is List
        ? data
        : (data is Map && data['items'] is List ? data['items'] as List : const []);
    return list
        .whereType<Map>()
        .map((e) => PayoutModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// `POST /wallet/payouts` → request a withdrawal. For [method] `UPI` pass
  /// [upiId]; for `BANK_TRANSFER` pass [bankAccountName], [bankAccountNumber]
  /// and [ifsc]. Returns the created [PayoutModel].
  Future<PayoutModel> requestPayout({
    required double amount,
    required String method,
    String? upiId,
    String? bankAccountName,
    String? bankAccountNumber,
    String? ifsc,
  }) async {
    final data = await _api.postJson(
      '/wallet/payouts',
      body: {
        'amount': amount,
        'method': method,
        if (method == 'UPI' && upiId != null && upiId.trim().isNotEmpty)
          'upiId': upiId.trim(),
        if (method == 'BANK_TRANSFER') ...{
          if (bankAccountName != null && bankAccountName.trim().isNotEmpty)
            'bankAccountName': bankAccountName.trim(),
          if (bankAccountNumber != null && bankAccountNumber.trim().isNotEmpty)
            'bankAccountNumber': bankAccountNumber.trim(),
          if (ifsc != null && ifsc.trim().isNotEmpty) 'ifsc': ifsc.trim(),
        },
      },
    );
    final map = J.asMap(data);
    final payoutJson = map['payout'] is Map ? J.asMap(map['payout']) : map;
    return PayoutModel.fromJson(payoutJson);
  }

  List<TransactionModel> _asTransactionList(dynamic data) {
    final list = data is List
        ? data
        : (data is Map && data['items'] is List
            ? data['items'] as List
            : const []);
    return list
        .whereType<Map>()
        .map((e) => TransactionModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  bool _hasMore(dynamic meta, int page, int limit, int received) {
    if (meta is Map && meta['total'] != null) {
      final total = int.tryParse(meta['total'].toString()) ?? 0;
      return page * limit < total;
    }
    return received >= limit;
  }
}

/// App-wide [WalletRepository] provider, wired to the shared [ApiClient].
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(apiClientProvider));
});
