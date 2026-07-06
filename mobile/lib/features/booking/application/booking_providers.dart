import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/booking/application/booking_flow_controller.dart';
import 'package:companion_ranchi/features/booking/data/booking_quote.dart';
import 'package:companion_ranchi/features/booking/data/booking_repository.dart';

/// The companion being booked (`GET /companions/:id`). Drives the rate shown
/// in the flow and the booking confirmation summary.
final bookingCompanionProvider =
    FutureProvider.family<CompanionModel, String>((ref, companionId) async {
  final repo = ref.watch(bookingRepositoryProvider);
  return repo.fetchCompanion(companionId);
});

/// Arguments for an availability lookup (companion + date).
class AvailabilityArgs {
  const AvailabilityArgs({required this.companionId, required this.date});

  final String companionId;
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is AvailabilityArgs &&
      other.companionId == companionId &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode =>
      Object.hash(companionId, date.year, date.month, date.day);
}

/// Available time slots for a companion on a given date
/// (`GET /companions/:id/availability?date=`).
final availabilityProvider =
    FutureProvider.family<List<TimeSlot>, AvailabilityArgs>((ref, args) async {
  final repo = ref.watch(bookingRepositoryProvider);
  return repo.fetchAvailability(
    companionId: args.companionId,
    date: args.date,
  );
});

/// The booking flow controller, scoped per companion.
///
/// The companion model is *read once* (not watched) so the controller is not
/// rebuilt — and the in-progress flow state wiped — when the companion profile
/// finishes loading. The screen watches [bookingCompanionProvider] separately
/// to render the live companion header.
final bookingFlowProvider = StateNotifierProvider.family<BookingFlowController,
    BookingFlowState, String>((ref, companionId) {
  final repo = ref.watch(bookingRepositoryProvider);
  final companion =
      ref.read(bookingCompanionProvider(companionId)).valueOrNull;
  return BookingFlowController(repo, companionId, companion);
});
