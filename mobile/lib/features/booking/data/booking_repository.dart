import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/booking/data/booking_quote.dart';

/// Data access for the booking creation flow. Talks to the `/bookings` and
/// `/companions/:id/availability` endpoints (API.md) and maps responses into
/// the shared models.
class BookingRepository {
  BookingRepository(this._api);

  final ApiClient _api;

  /// `GET /companions/:id` — full profile (rate, photos, availability) used to
  /// seed the booking flow (hourly rate, name, verification).
  Future<CompanionModel> fetchCompanion(String companionId) async {
    final data = await _api.getJson('/companions/$companionId');
    return CompanionModel.fromJson(J.asMap(data));
  }

  /// `GET /companions/:id/availability?date=YYYY-MM-DD` — bookable slots for the
  /// chosen day (already excludes booked slots, server-side). Filters out any
  /// slot explicitly flagged unavailable.
  Future<List<TimeSlot>> fetchAvailability({
    required String companionId,
    required DateTime date,
  }) async {
    final data = await _api.getJson(
      '/companions/$companionId/availability',
      query: {'date': Formatters.apiDate(date)},
    );

    // The endpoint may return either a bare list of slots or an object such as
    // `{ slots: [...] }` / `{ available: [...] }`. Normalise both.
    final List<dynamic> rawSlots;
    if (data is List) {
      rawSlots = data;
    } else if (data is Map) {
      final inner = data['slots'] ?? data['available'] ?? data['times'];
      rawSlots = inner is List ? inner : const [];
    } else {
      rawSlots = const [];
    }

    return rawSlots
        .map((e) {
          if (e is Map) return TimeSlot.fromJson(Map<String, dynamic>.from(e));
          // A bare "HH:mm" string slot: treat as a 1-hour window start.
          final s = e.toString();
          return TimeSlot(startTime: s, endTime: s);
        })
        .where((slot) => slot.isAvailable && slot.startTime.isNotEmpty)
        .toList(growable: false);
  }

  /// `POST /bookings/quote` — price breakdown, no DB write.
  Future<BookingQuote> quote({
    required String companionId,
    required int durationHours,
  }) async {
    final data = await _api.postJson(
      '/bookings/quote',
      body: {
        'companionId': companionId,
        'durationHours': durationHours,
      },
    );
    return BookingQuote.fromJson(J.asMap(data));
  }

  /// `POST /bookings` — create a PENDING booking (server validates slot
  /// availability + public meeting place, and provisions a Razorpay order).
  /// Returns the created [BookingModel] whose `id` drives `/payment/:bookingId`.
  Future<BookingModel> create({
    required String companionId,
    String? categoryId,
    required String activity,
    required int durationHours,
    required DateTime bookingDate,
    required String startTime,
    required String meetingLocation,
    required String meetingPlaceType,
    String? notes,
    String paymentMethod = 'razorpay',
  }) async {
    final data = await _api.postJson(
      '/bookings',
      body: {
        'companionId': companionId,
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        'activity': activity,
        'durationHours': durationHours,
        'bookingDate': Formatters.apiDate(bookingDate),
        'startTime': startTime,
        'meetingLocation': meetingLocation,
        'meetingPlaceType': meetingPlaceType,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'paymentMethod': paymentMethod,
      },
    );
    // The endpoint returns the booking (possibly wrapped as `{ booking, ... }`).
    final map = J.asMap(data);
    final bookingJson =
        map['booking'] is Map ? J.asMap(map['booking']) : map;
    return BookingModel.fromJson(bookingJson);
  }
}

/// Provider for [BookingRepository].
final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(apiClientProvider));
});
