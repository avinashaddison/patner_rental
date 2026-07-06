import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/transaction_model.dart';
import 'package:companion_ranchi/core/models/wallet_model.dart';
import 'package:companion_ranchi/features/wallet/data/wallet_repository.dart';

/// Wallet summary (`GET /wallet`): balance, pending, earned, withdrawn.
final walletSummaryProvider =
    FutureProvider.autoDispose<WalletModel>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return repo.fetchWallet();
});

/// Companion payout history (`GET /wallet/payouts`).
final payoutsProvider =
    FutureProvider.autoDispose<List<PayoutModel>>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return repo.fetchPayouts();
});

/// Paginated wallet ledger with infinite scroll. Holds the accumulated list,
/// the current page and whether more pages remain.
class TransactionsState {
  const TransactionsState({
    this.transactions = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 0,
    this.error,
  });

  final List<TransactionModel> transactions;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final Object? error;

  bool get isInitialLoading => transactions.isEmpty && error == null && page == 0;

  TransactionsState copyWith({
    List<TransactionModel>? transactions,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    Object? error,
    bool clearError = false,
  }) {
    return TransactionsState(
      transactions: transactions ?? this.transactions,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the wallet transactions list: initial load, pagination and refresh.
class TransactionsController extends AutoDisposeNotifier<TransactionsState> {
  WalletRepository get _repo => ref.read(walletRepositoryProvider);

  @override
  TransactionsState build() {
    // Kick off the first page lazily after construction.
    Future.microtask(loadInitial);
    return const TransactionsState();
  }

  /// Load (or reload) the first page, replacing any existing data.
  Future<void> loadInitial() async {
    state = state.copyWith(
      isLoadingMore: true,
      clearError: true,
      transactions: const [],
      page: 0,
      hasMore: true,
    );
    try {
      final result = await _repo.fetchTransactions(page: 1);
      state = TransactionsState(
        transactions: result.transactions,
        hasMore: result.hasMore,
        page: 1,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  /// Fetch the next page and append it.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final next = state.page + 1;
      final result = await _repo.fetchTransactions(page: next);
      state = state.copyWith(
        transactions: [...state.transactions, ...result.transactions],
        hasMore: result.hasMore,
        page: next,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  /// Pull-to-refresh: reload from the first page.
  Future<void> refresh() => loadInitial();
}

final transactionsControllerProvider =
    AutoDisposeNotifierProvider<TransactionsController, TransactionsState>(
  TransactionsController.new,
);

/// Outcome of a payout request, used to drive the withdraw sheet UI.
class PayoutController extends AutoDisposeNotifier<AsyncValue<PayoutModel?>> {
  WalletRepository get _repo => ref.read(walletRepositoryProvider);

  @override
  AsyncValue<PayoutModel?> build() => const AsyncData(null);

  /// Submit a withdrawal. On success, invalidates the wallet + payout providers
  /// so balances refresh. Returns true on success.
  Future<bool> submit({
    required double amount,
    required String method,
    String? upiId,
    String? bankAccountName,
    String? bankAccountNumber,
    String? ifsc,
  }) async {
    state = const AsyncLoading();
    try {
      final payout = await _repo.requestPayout(
        amount: amount,
        method: method,
        upiId: upiId,
        bankAccountName: bankAccountName,
        bankAccountNumber: bankAccountNumber,
        ifsc: ifsc,
      );
      state = AsyncData(payout);
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(payoutsProvider);
      ref.read(transactionsControllerProvider.notifier).refresh();
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final payoutControllerProvider = AutoDisposeNotifierProvider<PayoutController,
    AsyncValue<PayoutModel?>>(PayoutController.new);
