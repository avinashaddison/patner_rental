import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/payment/application/payment_controller.dart';
import 'package:companion_ranchi/features/payment/data/payment_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Razorpay checkout for a booking:
/// `POST /payments/order` -> open Razorpay -> on success `POST /payments/verify`
/// -> Booking Confirmation with the `bookingCode`.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with WidgetsBindingObserver {
  late final Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // Returning from the UPI app / browser — check the payment right away.
    if (lifecycleState == AppLifecycleState.resumed) {
      final state = ref.read(paymentControllerProvider(widget.bookingId));
      if (state.isUpiWaiting || state.isQrWaiting) _controller.checkUpiNow();
    }
  }

  /// Start the self-hosted QR flow: the QR renders in-app and the backend
  /// confirms once the bank credit is matched.
  Future<void> _openQr() async {
    await _controller.startQrPayment();
  }

  PaymentController get _controller =>
      ref.read(paymentControllerProvider(widget.bookingId).notifier);

  void _onSuccess(PaymentSuccessResponse response) {
    AppSounds.success();
    _controller.onCheckoutSuccess(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
  }

  void _onError(PaymentFailureResponse response) {
    AppSounds.error();
    final message = (response.message != null && response.message!.isNotEmpty)
        ? response.message!
        : 'Payment was cancelled or failed. You can try again.';
    _controller.onCheckoutError(message);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // The wallet selection still routes through the success/error events on
    // completion; nothing to confirm here yet.
  }

  /// Start the UPI (UPIGateway) flow: create the order, open the hosted
  /// payment page externally, and let the controller poll for confirmation.
  Future<void> _openUpi() async {
    final order = await _controller.startUpiPayment();
    if (order == null || !mounted) return;

    final uri = Uri.tryParse(order.paymentUrl);
    if (uri == null || order.paymentUrl.isEmpty) {
      _controller.onCheckoutError('Invalid UPI payment link. Please try again.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _controller.cancelUpiFlow();
      _controller.onCheckoutError('Could not open the UPI payment page.');
    }
  }

  void _openCheckout(RazorpayOrder order) {
    final user = ref.read(currentUserProvider);
    _controller.markProcessing();

    final options = <String, dynamic>{
      'key': order.keyId,
      'order_id': order.razorpayOrderId,
      'amount': order.amountInPaise,
      'currency': order.currency,
      'name': AppConstants.appName,
      'description': 'Companion booking',
      'timeout': 300,
      'prefill': {
        if (user != null) 'contact': user.mobileNumber,
        if (user?.email != null) 'email': user!.email,
        if (user != null) 'name': user.fullName,
      },
      // Brand pink to match the app (was an off-theme violet).
      'theme': {'color': '#FF4D6D'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      _controller.onCheckoutError('Could not open the payment sheet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentControllerProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        automaticallyImplyLeading: !state.isProcessing,
      ),
      body: SafeArea(
        child: switch (state.phase) {
          PaymentPhase.loading =>
            const LoadingView(message: 'Preparing your payment…'),
          PaymentPhase.failed => _FailedView(
              message: state.errorMessage,
              onRetry: () => _controller.retry(),
              onClose: () => context.go(Routes.bookings),
            ),
          PaymentPhase.success => _SuccessView(
              booking: state.confirmedBooking ?? state.booking,
            ),
          PaymentPhase.ready ||
          PaymentPhase.processing =>
            _PayView(
              state: state,
              onPay: state.order != null && !state.isProcessing
                  ? () => _openCheckout(state.order!)
                  : null,
              onPayUpi: !state.isProcessing ? _openUpi : null,
              onPayQr: !state.isProcessing ? _openQr : null,
              onCheckUpi: () => _controller.checkUpiNow(),
              onCancelUpi: () => _controller.cancelUpiFlow(),
              onReopenUpi: state.upiOrder != null
                  ? () => launchUrl(
                        Uri.parse(state.upiOrder!.paymentUrl),
                        mode: LaunchMode.externalApplication,
                      )
                  : null,
              onOpenUpiApp: state.qrOrder != null
                  ? () => launchUrl(
                        Uri.parse(state.qrOrder!.upiIntent),
                        mode: LaunchMode.externalApplication,
                      )
                  : null,
              onSubmitUtr: _controller.submitUtr,
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready / processing — breakdown + Pay button
// ---------------------------------------------------------------------------

class _PayView extends StatelessWidget {
  const _PayView({
    required this.state,
    required this.onPay,
    required this.onPayUpi,
    required this.onPayQr,
    required this.onCheckUpi,
    required this.onCancelUpi,
    required this.onReopenUpi,
    required this.onOpenUpiApp,
    required this.onSubmitUtr,
  });

  final PaymentState state;
  final VoidCallback? onPay;
  final VoidCallback? onPayUpi;
  final VoidCallback? onPayQr;
  final VoidCallback onCheckUpi;
  final VoidCallback onCancelUpi;
  final VoidCallback? onReopenUpi;
  final VoidCallback? onOpenUpiApp;

  /// Manual UTR check — returns null on success, or an error message.
  final Future<String?> Function(String utr) onSubmitUtr;

  @override
  Widget build(BuildContext context) {
    final booking = state.booking;
    final upiWaiting = state.isUpiWaiting;
    final qrWaiting = state.isQrWaiting;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (qrWaiting) ...[
                _QrPayCard(
                  qr: state.qrOrder!,
                  onOpenApp: onOpenUpiApp,
                  onSubmitUtr: onSubmitUtr,
                ),
                const SizedBox(height: AppSpacing.lg),
              ] else if (booking != null) ...[
                _BookingHeaderCard(booking: booking),
                const SizedBox(height: AppSpacing.lg),
                _PaymentBreakdown(booking: booking),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (upiWaiting) ...[
                _UpiWaitingNote(onReopen: onReopenUpi),
                const SizedBox(height: AppSpacing.lg),
              ] else if (state.isProcessing && !qrWaiting) ...[
                const _ProcessingNote(),
                const SizedBox(height: AppSpacing.lg),
              ],
              const SafetyBanner(),
              const SizedBox(height: AppSpacing.md),
              const _SecureNote(),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          decoration: const BoxDecoration(
            color: AppColors.scaffold,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (booking != null && !qrWaiting)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(
                        child: Text(
                          'Amount payable',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        Formatters.money(booking.totalAmount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              if (upiWaiting || qrWaiting) ...[
                GradientButton(
                  label: 'I\'ve completed the payment',
                  icon: Icons.task_alt_rounded,
                  onPressed: onCheckUpi,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton.text(
                  label: 'Cancel and choose another method',
                  expanded: true,
                  onPressed: onCancelUpi,
                ),
              ] else if (state.isProcessing) ...[
                const GradientButton(
                  label: 'Processing…',
                  isLoading: true,
                  onPressed: null,
                ),
              ] else ...[
                // Self-hosted QR first (no gateway commission), then fallbacks.
                GradientButton(
                  label: 'Pay via UPI QR',
                  icon: Icons.qr_code_2_rounded,
                  onPressed: onPayQr,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton.outline(
                  label: 'Pay with any UPI app',
                  icon: Icons.account_balance_wallet_rounded,
                  onPressed: onPayUpi,
                ),
                if (state.order != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton.text(
                    label: 'Pay by card (Razorpay)',
                    expanded: true,
                    onPressed: onPay,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// In-app dynamic UPI QR card — scan with any UPI app or tap through.
/// The paise-exact amount is how the payment is matched, so it is shown big
/// and the user is told not to change it.
class _QrPayCard extends StatefulWidget {
  const _QrPayCard({
    required this.qr,
    required this.onOpenApp,
    required this.onSubmitUtr,
  });

  final QrOrder qr;
  final VoidCallback? onOpenApp;
  final Future<String?> Function(String utr) onSubmitUtr;

  @override
  State<_QrPayCard> createState() => _QrPayCardState();
}

class _QrPayCardState extends State<_QrPayCard> {
  final _utrController = TextEditingController();
  bool _checking = false;
  String? _utrError;

  @override
  void dispose() {
    _utrController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final utr = _utrController.text.trim();
    if (utr.length < 9) {
      setState(() => _utrError = 'Enter the 12-digit UTR from your UPI app.');
      return;
    }
    setState(() {
      _checking = true;
      _utrError = null;
    });
    final err = await widget.onSubmitUtr(utr);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _utrError = err; // null on success (screen transitions away)
    });
  }

  @override
  Widget build(BuildContext context) {
    final qr = widget.qr;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Text(
            'Scan to pay',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${qr.payeeName} · ${qr.vpa}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: AppColors.line),
            ),
            child: QrImageView(
              data: qr.upiIntent,
              version: QrVersions.auto,
              size: 220,
              gapless: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pay exactly ₹${qr.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'This amount is unique to your order — please don\'t change it. '
            'Your booking confirms automatically after payment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.md),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'Waiting for payment… QR valid ~15 minutes',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
              ),
            ],
          ),
          if (widget.onOpenApp != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton.outline(
              label: 'Open UPI app instead',
              icon: Icons.open_in_new_rounded,
              onPressed: widget.onOpenApp,
            ),
          ],

          // Manual fallback: confirm by the UTR / reference number.
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: AppSpacing.md),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Already paid? Enter UTR Number',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _utrController,
            keyboardType: TextInputType.number,
            enabled: !_checking,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'e.g. 650321330050',
              errorText: _utrError,
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'The UTR / UPI transaction ID appears in your UPI app after paying.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GradientButton(
            label: 'Check payment status',
            icon: _checking ? null : Icons.search_rounded,
            isLoading: _checking,
            onPressed: _checking ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Shown while we wait for the UPI payment to be confirmed by the gateway.
class _UpiWaitingNote extends StatelessWidget {
  const _UpiWaitingNote({required this.onReopen});

  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Waiting for your UPI payment. Complete it in the page that '
                  'opened, then come back here — we\'ll confirm automatically.',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (onReopen != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton.text(
                label: 'Reopen payment page',
                icon: Icons.open_in_new_rounded,
                onPressed: onReopen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline reassurance shown while the Razorpay sheet is open / verifying.
class _ProcessingNote extends StatelessWidget {
  const _ProcessingNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Completing your payment securely. Please don\'t close this '
              'screen or press back.',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingHeaderCard extends StatelessWidget {
  const _BookingHeaderCard({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    final companion = booking.companion;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          UserAvatar(
            photoUrl: companion?.photoUrl,
            name: companion?.name ?? booking.activity,
            radius: 26,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companion?.name ?? 'Your companion',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${booking.activity} · ${Formatters.durationHours(booking.durationHours)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                  ),
                ),
                if (booking.bookingDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${Formatters.dateShort(booking.bookingDate!)} · ${Formatters.time12(booking.startTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _Row(
            label:
                '${Formatters.ratePerHour(booking.hourlyRate)} × ${booking.durationHours}',
            value: Formatters.money(booking.totalAmount),
          ),
          const Divider(height: AppSpacing.lg),
          _Row(
            label: 'Total',
            value: Formatters.money(booking.totalAmount),
            emphasised: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final weight = emphasised ? FontWeight.w800 : FontWeight.w500;
    final size = emphasised ? 17.0 : 14.5;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: weight,
              fontSize: size,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: weight,
            fontSize: size,
            color: emphasised ? AppColors.primary : AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _SecureNote extends StatelessWidget {
  const _SecureNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_rounded, size: 14, color: AppColors.inkMuted),
        SizedBox(width: 6),
        Text(
          'Payments secured by Razorpay & UPI',
          style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Success — booking confirmation
// ---------------------------------------------------------------------------

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.booking});

  final BookingModel? booking;

  @override
  Widget build(BuildContext context) {
    final code = booking?.bookingCode ?? '';
    return _CenteredStatusLayout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Booking confirmed!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Your payment was successful and your companion has been notified.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 14.5),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BOOKING CODE',
                    style: TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      letterSpacing: 1.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientButton(
            label: 'View booking',
            icon: Icons.receipt_long_rounded,
            onPressed: () {
              if (booking != null) {
                context.go(Routes.bookingDetailPath(booking!.id));
              } else {
                context.go(Routes.bookings);
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Back to my bookings',
            expanded: true,
            onPressed: () => context.go(Routes.bookings),
          ),
        ],
      ),
    );
  }
}

/// Centered status layout (icon + title + body) that stays scrollable so it
/// never overflows at large text scales, with the action buttons pinned below.
class _CenteredStatusLayout extends StatelessWidget {
  const _CenteredStatusLayout({required this.content, required this.actions});

  final Widget content;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - AppSpacing.xl * 2,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: Center(child: content),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  actions,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Failed
// ---------------------------------------------------------------------------

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _CenteredStatusLayout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Payment incomplete',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 14.5),
          ),
        ],
      ),
      actions: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Pay later from My Bookings',
            expanded: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
