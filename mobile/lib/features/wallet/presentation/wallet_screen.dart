import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/transaction_model.dart';
import 'package:companion_ranchi/core/models/wallet_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/wallet/application/wallet_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Wallet hub: live balance summary, the immutable transaction ledger and — for
/// companions — a withdraw (payout) flow supporting UPI or bank transfer.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 280) {
      ref.read(transactionsControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(walletSummaryProvider);
    await ref.read(transactionsControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(walletSummaryProvider);
    final txState = ref.watch(transactionsControllerProvider);
    final user = ref.watch(currentUserProvider);
    final isCompanion = user?.isCompanion ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: summary.when(
                  loading: () => const _BalanceSkeleton(),
                  error: (e, _) => _BalanceError(
                    onRetry: () => ref.invalidate(walletSummaryProvider),
                  ),
                  data: (wallet) => _BalanceCard(
                    wallet: wallet,
                    isCompanion: isCompanion,
                    onWithdraw: isCompanion
                        ? () => _openWithdrawSheet(context, wallet)
                        : null,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Transactions',
                subtitle: 'Your wallet ledger',
              ),
            ),
            _buildTransactions(txState),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactions(TransactionsState state) {
    if (state.isInitialLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: LoadingView(),
        ),
      );
    }
    if (state.transactions.isEmpty && state.error != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: ErrorView(
            error: state.error,
            onRetry: () =>
                ref.read(transactionsControllerProvider.notifier).loadInitial(),
          ),
        ),
      );
    }
    if (state.transactions.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: EmptyView(
            icon: Icons.receipt_long_rounded,
            title: 'No transactions yet',
            message:
                'Your earnings, refunds and referral rewards will appear here.',
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= state.transactions.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: state.hasMore
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(
                        'No more transactions',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.inkMuted),
                      ),
              ),
            );
          }
          return _TransactionTile(tx: state.transactions[index]);
        },
        childCount: state.transactions.length + 1,
      ),
    );
  }

  Future<void> _openWithdrawSheet(
    BuildContext context,
    WalletModel wallet,
  ) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WithdrawSheet(available: wallet.balance),
    );
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Withdrawal request submitted.')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.wallet,
    required this.isCompanion,
    required this.onWithdraw,
  });

  final WalletModel wallet;
  final bool isCompanion;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        // "Green = money" — same emerald family as the dashboard earnings hero.
        gradient: AppGradients.money,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.money.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Available balance',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.moneySmart(wallet.balance),
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: isCompanion ? 'Pending' : 'On hold',
                  value: Formatters.moneySmart(wallet.pendingBalance),
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Earned',
                  value: Formatters.moneySmart(wallet.totalEarned),
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Withdrawn',
                  value: Formatters.moneySmart(wallet.totalWithdrawn),
                  icon: Icons.north_east_rounded,
                ),
              ),
            ],
          ),
          if (isCompanion) ...[
            const SizedBox(height: AppSpacing.xl),
            if (wallet.balance >= AppConstants.minPayout)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onWithdraw,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.money,
                  ),
                  icon: const Icon(Icons.payments_rounded, size: 20),
                  label: const Text('Withdraw'),
                ),
              )
            else
              _WithdrawProgress(balance: wallet.balance),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        // Darken (not lighten) the tile so white text keeps its contrast.
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 16),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Below the payout threshold: a progress bar toward the ₹500 minimum with the
/// exact amount still needed — a goal, not a dead disabled button.
class _WithdrawProgress extends StatelessWidget {
  const _WithdrawProgress({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    const target = AppConstants.minPayout;
    final progress = (balance / target).clamp(0.0, 1.0);
    final remaining = (target - balance).clamp(0, target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.black.withValues(alpha: 0.22),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${Formatters.moneySmart(remaining)} more to unlock withdrawals',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppGradients.money,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.money.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmer(width: 130, height: 14),
          const SizedBox(height: 14),
          _shimmer(width: 190, height: 34),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: _shimmer(height: 58)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(height: 58)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(height: 58)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmer({double width = double.infinity, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
    );
  }
}

/// Balance error state — keeps the premium gold card footprint and offers a
/// retry that re-fetches [walletSummaryProvider].
class _BalanceError extends StatelessWidget {
  const _BalanceError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: AppColors.danger, size: 26),
          ),
          const SizedBox(height: 14),
          const Text(
            "Couldn't load your balance",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction tile
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final TransactionModel tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
    final color = isCredit ? AppColors.success : AppColors.danger;
    final sign = isCredit ? '+' : '-';
    final amount =
        '$sign ${Formatters.money(tx.amount.abs())}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 4,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(_iconFor(tx.type), color: color, size: 20),
      ),
      title: Text(
        tx.description?.isNotEmpty == true
            ? tx.description!
            : TransactionModel.typeLabel(tx.type),
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          TransactionModel.typeLabel(tx.type),
          if (tx.createdAt != null) Formatters.dateTime(tx.createdAt!),
        ].join(' • '),
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (tx.status != 'COMPLETED')
            Text(
              tx.status == 'PENDING' ? 'Pending' : 'Failed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tx.status == 'PENDING'
                    ? AppColors.warning
                    : AppColors.danger,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'BOOKING_EARNING':
        return Icons.event_available_rounded;
      case 'PAYOUT':
        return Icons.north_east_rounded;
      case 'REFUND':
        return Icons.replay_rounded;
      case 'COMMISSION':
        return Icons.percent_rounded;
      case 'REFERRAL_REWARD':
        return Icons.card_giftcard_rounded;
      case 'CREDIT':
        return Icons.south_west_rounded;
      case 'DEBIT':
        return Icons.north_east_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// Withdraw sheet (companion only)
// ---------------------------------------------------------------------------

class _WithdrawSheet extends ConsumerStatefulWidget {
  const _WithdrawSheet({required this.available});

  final double available;

  @override
  ConsumerState<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<_WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _upiController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscController = TextEditingController();

  String _method = 'UPI';

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.available.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _upiController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.trim());
    final ok = await ref.read(payoutControllerProvider.notifier).submit(
          amount: amount,
          method: _method,
          upiId: _method == 'UPI' ? _upiController.text : null,
          bankAccountName:
              _method == 'BANK_TRANSFER' ? _accountNameController.text : null,
          bankAccountNumber:
              _method == 'BANK_TRANSFER' ? _accountNumberController.text : null,
          ifsc: _method == 'BANK_TRANSFER' ? _ifscController.text : null,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payoutState = ref.watch(payoutControllerProvider);
    final isSubmitting = payoutState.isLoading;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Withdraw earnings',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Available: ${Formatters.moneyPrecise(widget.available)}',
                style: const TextStyle(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _amountController,
                label: 'Amount (₹)',
                hint: 'Enter amount to withdraw',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                validator: _validateAmount,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Payout method',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'UPI',
                    label: Text('UPI'),
                    icon: Icon(Icons.qr_code_rounded),
                  ),
                  ButtonSegment(
                    value: 'BANK_TRANSFER',
                    label: Text('Bank'),
                    icon: Icon(Icons.account_balance_rounded),
                  ),
                ],
                selected: {_method},
                onSelectionChanged: (s) => setState(() => _method = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_method == 'UPI')
                AppTextField(
                  controller: _upiController,
                  label: 'UPI ID',
                  hint: 'yourname@upi',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter your UPI ID';
                    if (!value.contains('@')) return 'Enter a valid UPI ID';
                    return null;
                  },
                )
              else ...[
                AppTextField(
                  controller: _accountNameController,
                  label: 'Account holder name',
                  hint: 'As per bank records',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Enter the account holder name'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _accountNumberController,
                  label: 'Account number',
                  hint: 'Bank account number',
                  keyboardType: TextInputType.number,
                  prefixIcon: const Icon(Icons.numbers_rounded),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.length < 6) return 'Enter a valid account number';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _ifscController,
                  label: 'IFSC code',
                  hint: 'e.g. SBIN0001234',
                  prefixIcon: const Icon(Icons.account_balance_rounded),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                  ],
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value)) {
                      return 'Enter a valid IFSC code';
                    }
                    return null;
                  },
                ),
              ],
              if (payoutState.hasError) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _errorText(payoutState.error),
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: 'Request withdrawal',
                icon: Icons.send_rounded,
                isLoading: isSubmitting,
                onPressed: isSubmitting ? null : _submit,
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Payouts are processed within 1-3 business days.',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateAmount(String? v) {
    final value = double.tryParse(v?.trim() ?? '');
    if (value == null || value <= 0) return 'Enter a valid amount';
    if (value < AppConstants.minPayout) {
      return 'Minimum withdrawal is ${Formatters.money(AppConstants.minPayout)}';
    }
    if (value > widget.available) {
      return 'Amount exceeds available balance';
    }
    return null;
  }

  String _errorText(Object? error) {
    if (error is ApiException) return error.message;
    return 'Withdrawal failed. Please try again.';
  }
}

/// Forces input to upper case (used for IFSC codes).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
