import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/features/bookings/data/bookings_repository.dart';
import 'package:companion_ranchi/features/payment/data/payment_repository.dart';

/// Lifecycle phases of the payment screen.
enum PaymentPhase {
  /// Loading the booking + creating the Razorpay order.
  loading,

  /// Order ready; waiting for the user to tap Pay (or the sheet to open).
  ready,

  /// Razorpay checkout sheet is open / awaiting the gateway.
  processing,

  /// Signature verified, booking confirmed.
  success,

  /// Loading, order creation or verification failed.
  failed,
}

/// Immutable state of the payment flow for a single booking.
@immutable
class PaymentState {
  const PaymentState({
    this.phase = PaymentPhase.loading,
    this.booking,
    this.order,
    this.upiOrder,
    this.qrOrder,
    this.confirmedBooking,
    this.error,
  });

  final PaymentPhase phase;

  /// The booking being paid for (price breakdown, companion, etc.).
  final BookingModel? booking;

  /// The Razorpay order (id, amount, keyId) once provisioned.
  final RazorpayOrder? order;

  /// The UPIGateway order once the user chose "Pay with UPI". While set and
  /// [isProcessing], the controller is polling the gateway for confirmation.
  final UpiOrder? upiOrder;

  /// The self-hosted QR order once the user chose "Scan & pay". While set and
  /// [isProcessing], the controller polls until the bank credit is matched.
  final QrOrder? qrOrder;

  /// The confirmed booking returned by `/payments/verify` (carries the code).
  final BookingModel? confirmedBooking;

  final Object? error;

  bool get isLoading => phase == PaymentPhase.loading;
  bool get isReady => phase == PaymentPhase.ready;
  bool get isProcessing => phase == PaymentPhase.processing;
  bool get isSuccess => phase == PaymentPhase.success;
  bool get isFailed => phase == PaymentPhase.failed;

  String get errorMessage {
    final e = error;
    if (e is ApiException) return e.message;
    if (e is String) return e;
    return 'Payment could not be completed. Please try again.';
  }

  /// Whether the processing phase belongs to the UPI (gateway-polling) flow.
  bool get isUpiWaiting => isProcessing && upiOrder != null;

  /// Whether the processing phase belongs to the in-app QR flow.
  bool get isQrWaiting => isProcessing && qrOrder != null;

  PaymentState copyWith({
    PaymentPhase? phase,
    BookingModel? booking,
    RazorpayOrder? order,
    Object? upiOrder = _sentinel,
    Object? qrOrder = _sentinel,
    BookingModel? confirmedBooking,
    Object? error = _sentinel,
  }) {
    return PaymentState(
      phase: phase ?? this.phase,
      booking: booking ?? this.booking,
      order: order ?? this.order,
      upiOrder:
          upiOrder == _sentinel ? this.upiOrder : upiOrder as UpiOrder?,
      qrOrder: qrOrder == _sentinel ? this.qrOrder : qrOrder as QrOrder?,
      confirmedBooking: confirmedBooking ?? this.confirmedBooking,
      error: error == _sentinel ? this.error : error,
    );
  }

  static const Object _sentinel = Object();
}

/// Orchestrates the payment flow:
/// 1. Load the booking (`GET /bookings/:id`) to show the breakdown.
/// 2. Create / reuse the Razorpay order (`POST /payments/order`).
/// 3. The screen opens the Razorpay sheet; on success it calls [onCheckoutSuccess]
///    which verifies the signature (`POST /payments/verify`) and confirms.
class PaymentController extends StateNotifier<PaymentState> {
  PaymentController(this._payments, this._bookings, this.bookingId)
      : super(const PaymentState()) {
    initialise();
  }

  final PaymentRepository _payments;
  final BookingsRepository _bookings;
  final String bookingId;

  /// Load the booking and provision the Razorpay order.
  Future<void> initialise() async {
    _stopUpiPolling();
    state = const PaymentState(phase: PaymentPhase.loading);
    try {
      final booking = await _bookings.detail(bookingId);

      // Already paid? Treat as success so the user sees the confirmation.
      if (booking.payment?.isCaptured == true ||
          booking.status == BookingStatus.confirmed ||
          booking.status == BookingStatus.inProgress ||
          booking.status == BookingStatus.completed) {
        state = state.copyWith(
          phase: PaymentPhase.success,
          booking: booking,
          confirmedBooking: booking,
        );
        return;
      }

      // Razorpay order provisioning is best-effort: if the gateway is down or
      // unconfigured, the screen still opens with UPI as the available method.
      RazorpayOrder? order;
      try {
        order = await _payments.createOrder(bookingId);
      } catch (_) {
        order = null;
      }
      state = state.copyWith(
        phase: PaymentPhase.ready,
        booking: booking,
        order: order,
      );
    } catch (e) {
      state = state.copyWith(phase: PaymentPhase.failed, error: e);
    }
  }

  /// Marks the sheet as open (called right before `Razorpay.open`).
  void markProcessing() {
    _stopUpiPolling();
    state = state.copyWith(
      phase: PaymentPhase.processing,
      error: null,
      upiOrder: null,
      qrOrder: null,
    );
  }

  // ---------------------------------------------------------------------------
  // UPI (UPIGateway) flow: create order -> open paymentUrl -> poll verify.
  // ---------------------------------------------------------------------------

  Timer? _upiTimer;
  DateTime? _upiStartedAt;

  /// How long we keep polling before giving up (gateway QR validity ~10 min).
  static const _upiTimeout = Duration(minutes: 8);
  static const _upiPollEvery = Duration(seconds: 4);

  /// Create a UPIGateway order and start polling for its confirmation.
  /// Returns the order (with `paymentUrl` for the screen to open), or null on
  /// failure (state moves to [PaymentPhase.failed]).
  Future<UpiOrder?> startUpiPayment() async {
    state = state.copyWith(
      phase: PaymentPhase.processing,
      error: null,
      qrOrder: null,
    );
    try {
      final order = await _payments.createUpiOrder(bookingId);
      state = state.copyWith(upiOrder: order);
      _startPolling();
      return order;
    } catch (e) {
      state = state.copyWith(phase: PaymentPhase.failed, error: e);
      return null;
    }
  }

  /// Create a self-hosted UPI QR order (rendered in-app) and start polling.
  /// The backend confirms it when the bank's credit-alert email is matched.
  Future<QrOrder?> startQrPayment() async {
    state = state.copyWith(
      phase: PaymentPhase.processing,
      error: null,
      upiOrder: null,
    );
    try {
      final order = await _payments.createQrOrder(bookingId);
      state = state.copyWith(qrOrder: order);
      _startPolling();
      return order;
    } catch (e) {
      state = state.copyWith(phase: PaymentPhase.failed, error: e);
      return null;
    }
  }

  /// Immediate status check — called when the app returns to the foreground
  /// or the user taps "I've completed the payment".
  Future<void> checkUpiNow() => _pollUpi();

  /// Manual UTR fallback for the QR flow. The user pastes the UTR from their
  /// UPI app; on success we transition to [PaymentPhase.success]. Returns null
  /// on success, or a user-facing message when it's not confirmed yet.
  Future<String?> submitUtr(String utr) async {
    final qrOrder = state.qrOrder;
    if (qrOrder == null) return 'No active QR payment.';
    try {
      final res = await _payments.checkQrByUtr(qrOrder.ref, utr);
      if (!mounted) return null;
      if (res.isPaid) {
        _stopUpiPolling();
        BookingModel? confirmed;
        try {
          confirmed = await _bookings.detail(bookingId);
        } catch (_) {
          confirmed = state.booking;
        }
        state = state.copyWith(
          phase: PaymentPhase.success,
          confirmedBooking: confirmed ?? state.booking,
          booking: confirmed ?? state.booking,
        );
        return null;
      }
      return res.message;
    } catch (e) {
      return e is ApiException ? e.message : 'Could not check the payment. Try again.';
    }
  }

  /// Abandon the UPI/QR attempt and return to the method choice.
  void cancelUpiFlow() {
    _stopUpiPolling();
    state = state.copyWith(
      phase: PaymentPhase.ready,
      error: null,
      upiOrder: null,
      qrOrder: null,
    );
  }

  void _startPolling() {
    _upiStartedAt = DateTime.now();
    _upiTimer?.cancel();
    _upiTimer = Timer.periodic(_upiPollEvery, (_) => _pollUpi());
  }

  void _stopUpiPolling() {
    _upiTimer?.cancel();
    _upiTimer = null;
    _upiStartedAt = null;
  }

  Future<void> _pollUpi() async {
    final upiOrder = state.upiOrder;
    final qrOrder = state.qrOrder;
    if (!mounted || (upiOrder == null && qrOrder == null) || !state.isProcessing) {
      _stopUpiPolling();
      return;
    }

    try {
      final result = qrOrder != null
          ? await _payments.verifyQr(qrOrder.ref)
          : await _payments.verifyUpi(upiOrder!.clientTxnId);
      if (!mounted) return;

      if (result.isPaid) {
        _stopUpiPolling();
        // Reload the booking so the confirmation carries the booking code.
        BookingModel? confirmed;
        try {
          confirmed = await _bookings.detail(bookingId);
        } catch (_) {
          confirmed = state.booking;
        }
        state = state.copyWith(
          phase: PaymentPhase.success,
          confirmedBooking: confirmed ?? state.booking,
          booking: confirmed ?? state.booking,
        );
        return;
      }

      if (result.isFailed) {
        _stopUpiPolling();
        final expired = result.gatewayStatus == 'expired';
        state = state.copyWith(
          phase: PaymentPhase.failed,
          error: expired
              ? 'This QR expired before payment. Start again for a fresh QR.'
              : 'The UPI payment failed or was declined. Please try again.',
          upiOrder: null,
          qrOrder: null,
        );
        return;
      }
    } catch (_) {
      // Transient network error — keep polling until the timeout below.
    }

    // The in-app QR flow relies on the server-side expiry instead of a local
    // timeout (email confirmation can lag a paid-at-the-last-second QR).
    if (state.qrOrder != null) return;

    final startedAt = _upiStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) > _upiTimeout) {
      _stopUpiPolling();
      state = state.copyWith(
        phase: PaymentPhase.failed,
        error:
            'We could not confirm the payment in time. If money was deducted, '
            'it will be confirmed automatically — check My Bookings in a few minutes.',
        upiOrder: null,
      );
    }
  }

  @override
  void dispose() {
    _stopUpiPolling();
    super.dispose();
  }

  /// Called by the screen when Razorpay returns a successful payment. Verifies
  /// the signature server-side and, on success, transitions to [PaymentPhase.success].
  Future<void> onCheckoutSuccess({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    state = state.copyWith(phase: PaymentPhase.processing, error: null);
    try {
      final confirmed = await _payments.verify(
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      state = state.copyWith(
        phase: PaymentPhase.success,
        confirmedBooking: confirmed,
        booking: confirmed,
      );
    } catch (e) {
      state = state.copyWith(phase: PaymentPhase.failed, error: e);
    }
  }

  /// Called by the screen when Razorpay reports an error or the user cancels.
  void onCheckoutError(String message) {
    state = state.copyWith(phase: PaymentPhase.failed, error: message);
  }

  /// Retry from a failed state: re-load the booking + order.
  Future<void> retry() => initialise();
}

/// Payment flow provider, scoped per booking id.
final paymentControllerProvider = StateNotifierProvider.family<
    PaymentController, PaymentState, String>((ref, bookingId) {
  return PaymentController(
    ref.watch(paymentRepositoryProvider),
    ref.watch(bookingsRepositoryProvider),
    bookingId,
  );
});
