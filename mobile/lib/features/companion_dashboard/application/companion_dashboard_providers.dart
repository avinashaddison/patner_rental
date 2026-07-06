import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_models.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_repository.dart';

/// Summary cards (`GET /companion/dashboard`).
final companionDashboardProvider =
    FutureProvider.autoDispose<CompanionDashboard>((ref) async {
  final repo = ref.watch(companionDashboardRepositoryProvider);
  return repo.fetchDashboard();
});

/// Earnings breakdown + recent transactions (`GET /companion/earnings`).
final companionEarningsProvider =
    FutureProvider.autoDispose<CompanionEarnings>((ref) async {
  final repo = ref.watch(companionDashboardRepositoryProvider);
  return repo.fetchEarnings();
});

/// Upcoming (active) bookings for the dashboard list — PENDING/CONFIRMED/
/// IN_PROGRESS, sorted by booking date ascending.
final companionUpcomingBookingsProvider =
    FutureProvider.autoDispose<List<BookingModel>>((ref) async {
  final repo = ref.watch(companionDashboardRepositoryProvider);
  final all = await repo.fetchBookings();
  final upcoming = all.where((b) => b.isActive).toList()
    ..sort((a, b) {
      final ad = a.bookingDate;
      final bd = b.bookingDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
  return upcoming;
});

/// Pending booking requests awaiting accept/reject (status == PENDING).
final companionPendingRequestsProvider =
    FutureProvider.autoDispose<List<BookingModel>>((ref) async {
  final repo = ref.watch(companionDashboardRepositoryProvider);
  return repo.fetchBookings(status: BookingStatus.pending);
});

/// The signed-in companion's own profile (`GET /companions/me/profile`).
/// Resolves to `null` when the user hasn't onboarded as a companion.
final myCompanionProfileProvider =
    FutureProvider.autoDispose<CompanionModel?>((ref) async {
  final repo = ref.watch(companionDashboardRepositoryProvider);
  return repo.fetchMyProfile();
});

/// Convenience: refresh all dashboard data after a mutation.
void invalidateCompanionDashboard(Ref ref) {
  ref.invalidate(companionDashboardProvider);
  ref.invalidate(companionEarningsProvider);
  ref.invalidate(companionUpcomingBookingsProvider);
  ref.invalidate(companionPendingRequestsProvider);
}

void invalidateCompanionDashboardFromWidget(WidgetRef ref) {
  ref.invalidate(companionDashboardProvider);
  ref.invalidate(companionEarningsProvider);
  ref.invalidate(companionUpcomingBookingsProvider);
  ref.invalidate(companionPendingRequestsProvider);
}
