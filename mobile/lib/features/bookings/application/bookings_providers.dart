import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/features/bookings/data/bookings_repository.dart';

/// The tabs on the My Bookings screen and how each maps to backend statuses.
enum BookingTab {
  upcoming,
  active,
  completed,
  cancelled;

  String get label {
    switch (this) {
      case BookingTab.upcoming:
        return 'Upcoming';
      case BookingTab.active:
        return 'Active';
      case BookingTab.completed:
        return 'Completed';
      case BookingTab.cancelled:
        return 'Cancelled';
    }
  }

  /// Statuses that belong to this tab.
  List<String> get statuses {
    switch (this) {
      case BookingTab.upcoming:
        return const [BookingStatus.pending, BookingStatus.confirmed];
      case BookingTab.active:
        return const [BookingStatus.inProgress];
      case BookingTab.completed:
        return const [BookingStatus.completed];
      case BookingTab.cancelled:
        return const [BookingStatus.cancelled, BookingStatus.refunded];
    }
  }

  bool matches(String status) => statuses.contains(status);
}

/// All of the current user's bookings (role-aware server-side). A single fetch
/// powers every tab via client-side filtering, so switching tabs is instant and
/// pull-to-refresh refreshes everything.
final myBookingsProvider =
    FutureProvider.autoDispose<List<BookingModel>>((ref) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.list();
});

/// Bookings filtered to a given tab, sorted with the most relevant first.
final bookingsForTabProvider = Provider.autoDispose
    .family<AsyncValue<List<BookingModel>>, BookingTab>((ref, tab) {
  return ref.watch(myBookingsProvider).whenData((all) {
    final filtered =
        all.where((b) => tab.matches(b.status)).toList(growable: true);
    filtered.sort((a, b) {
      final ad = a.bookingDate ?? a.createdAt;
      final bd = b.bookingDate ?? b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      // Upcoming/active: soonest first. Completed/cancelled: most recent first.
      final ascending =
          tab == BookingTab.upcoming || tab == BookingTab.active;
      return ascending ? ad.compareTo(bd) : bd.compareTo(ad);
    });
    return filtered;
  });
});

/// Detail for a single booking (`GET /bookings/:id`), including statusHistory.
/// Cached briefly so back → reopen is instant; lifecycle actions and the payment
/// flow already `ref.invalidate` this provider, so status never shows stale.
final bookingDetailProvider =
    FutureProvider.autoDispose.family<BookingModel, String>((ref, id) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 60), link.close);
  ref.onDispose(timer.cancel);
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.detail(id);
});

/// Drives the lifecycle action buttons on the booking detail screen
/// (accept/reject/start/complete/cancel). The [AsyncValue] tracks the in-flight
/// action so the UI can show a spinner and disable buttons.
class BookingActionsController extends StateNotifier<AsyncValue<void>> {
  BookingActionsController(this._ref, this._repo, this.bookingId)
      : super(const AsyncData(null));

  final Ref _ref;
  final BookingsRepository _repo;
  final String bookingId;

  Future<BookingModel?> _run(Future<BookingModel> Function() action) async {
    state = const AsyncLoading();
    try {
      final updated = await action();
      state = const AsyncData(null);
      // Refresh detail + list so every view reflects the new status.
      _ref.invalidate(bookingDetailProvider(bookingId));
      _ref.invalidate(myBookingsProvider);
      return updated;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<BookingModel?> accept() => _run(() => _repo.accept(bookingId));
  Future<BookingModel?> reject() => _run(() => _repo.reject(bookingId));
  Future<BookingModel?> start(String code) =>
      _run(() => _repo.start(bookingId, code: code));
  Future<BookingModel?> complete() => _run(() => _repo.complete(bookingId));
  Future<BookingModel?> cancel(String reason) =>
      _run(() => _repo.cancel(bookingId, reason: reason));
}

/// Booking actions provider, scoped per booking id.
final bookingActionsProvider = StateNotifierProvider.autoDispose
    .family<BookingActionsController, AsyncValue<void>, String>((ref, id) {
  return BookingActionsController(
    ref,
    ref.watch(bookingsRepositoryProvider),
    id,
  );
});
