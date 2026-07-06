import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// Data access for listing and managing bookings (`/bookings`). Role-aware on
/// the backend: a customer sees their bookings, a companion sees received ones.
class BookingsRepository {
  BookingsRepository(this._api);

  final ApiClient _api;

  /// `GET /bookings?status=` — the current user's bookings, optionally filtered
  /// by a single status. The backend returns a paginated envelope; this returns
  /// just the list (most recent first, as ordered server-side).
  Future<List<BookingModel>> list({
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final env = await _api.getEnvelope(
      '/bookings',
      query: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
        'sort': 'createdAt:desc',
      },
    );
    final data = env['data'];
    return J
        .asMapList(data)
        .map(BookingModel.fromJson)
        .toList(growable: false);
  }

  /// `GET /bookings/:id` — full detail including `statusHistory` and `payment`.
  Future<BookingModel> detail(String id) async {
    final data = await _api.getJson('/bookings/$id');
    return BookingModel.fromJson(J.asMap(data));
  }

  // ---- Lifecycle actions (status machine, API.md §4) --------------------

  /// `POST /bookings/:id/accept` — companion accepts (PENDING/CONFIRMED →
  /// CONFIRMED).
  Future<BookingModel> accept(String id) => _action(id, 'accept');

  /// `POST /bookings/:id/reject` — companion rejects (→ CANCELLED, refund if
  /// paid).
  Future<BookingModel> reject(String id) => _action(id, 'reject');

  /// `POST /bookings/:id/start` — companion starts the meeting (CONFIRMED →
  /// IN_PROGRESS) by entering the customer's 6-digit start code.
  Future<BookingModel> start(String id, {required String code}) async {
    final data = await _api.postJson(
      '/bookings/$id/start',
      body: {'code': code},
    );
    return _parse(data, fallbackId: id);
  }

  /// `POST /bookings/:id/complete` — companion completes (IN_PROGRESS →
  /// COMPLETED; triggers payout credit + referral check).
  Future<BookingModel> complete(String id) => _action(id, 'complete');

  /// `POST /bookings/:id/cancel` — customer cancels with a reason (refund policy
  /// applies server-side).
  Future<BookingModel> cancel(String id, {required String reason}) async {
    final data = await _api.postJson(
      '/bookings/$id/cancel',
      body: {'reason': reason},
    );
    return _parse(data, fallbackId: id);
  }

  Future<BookingModel> _action(String id, String action) async {
    final data = await _api.postJson('/bookings/$id/$action');
    return _parse(data, fallbackId: id);
  }

  /// Action endpoints may return the updated booking, `{ booking: {...} }`, or
  /// just a status. Re-fetch the detail when the body isn't a usable booking.
  Future<BookingModel> _parse(dynamic data, {required String fallbackId}) async {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final bookingJson = map['booking'] is Map ? J.asMap(map['booking']) : map;
      if (bookingJson['id'] != null && bookingJson['status'] != null) {
        return BookingModel.fromJson(bookingJson);
      }
    }
    return detail(fallbackId);
  }
}

/// Provider for [BookingsRepository].
final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(apiClientProvider));
});
