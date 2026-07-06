import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_repository.dart';

/// The set of companion-side actions on an incoming booking.
enum BookingAction { accept, reject, start, complete }

/// Tracks which booking id (if any) currently has an action in flight, so the
/// dashboard can show a spinner on the relevant row only.
class BookingActionController extends Notifier<String?> {
  CompanionDashboardRepository get _repo =>
      ref.read(companionDashboardRepositoryProvider);

  @override
  String? build() => null;

  bool isBusy(String bookingId) => state == bookingId;

  /// Runs [action] on [bookingId], then refreshes the dashboard providers.
  /// Returns the updated booking. [code] is required for [BookingAction.start]
  /// (the customer's 6-digit meet-at-location code).
  Future<BookingModel> run(
    String bookingId,
    BookingAction action, {
    String? code,
  }) async {
    state = bookingId;
    try {
      final BookingModel updated;
      switch (action) {
        case BookingAction.accept:
          updated = await _repo.acceptBooking(bookingId);
          break;
        case BookingAction.reject:
          updated = await _repo.rejectBooking(bookingId);
          break;
        case BookingAction.start:
          updated = await _repo.startBooking(bookingId, code: code ?? '');
          break;
        case BookingAction.complete:
          updated = await _repo.completeBooking(bookingId);
          break;
      }
      invalidateCompanionDashboard(ref);
      return updated;
    } finally {
      state = null;
    }
  }
}

final bookingActionControllerProvider =
    NotifierProvider<BookingActionController, String?>(
  BookingActionController.new,
);
