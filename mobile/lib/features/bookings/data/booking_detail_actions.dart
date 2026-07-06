import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// Cross-cutting actions available from the booking detail screen that hit
/// endpoints outside `/bookings`: raising an SOS alert and opening a chat with
/// the other party. Kept thin and self-contained so the booking feature does
/// not depend on the (separately-owned) chat/safety features.
class BookingDetailActions {
  BookingDetailActions(this._api);

  final ApiClient _api;

  /// `POST /sos` — raise a safety alert tied to a booking. Returns the SOS id.
  Future<String> raiseSos({
    required String bookingId,
    double? latitude,
    double? longitude,
    String? message,
  }) async {
    final data = await _api.postJson(
      '/sos',
      body: {
        'bookingId': bookingId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'message': message ?? 'Emergency during an active booking.',
      },
    );
    return J.asString(J.asMap(data)['id']);
  }

  /// `POST /chat/conversations` — get-or-create the conversation with [peerUserId]
  /// (optionally tied to [bookingId]). Returns the conversation id for routing
  /// to `/chat/:conversationId`.
  Future<String> openConversation({
    required String peerUserId,
    String? bookingId,
  }) async {
    final data = await _api.postJson(
      '/chat/conversations',
      body: {
        'peerUserId': peerUserId,
        if (bookingId != null) 'bookingId': bookingId,
      },
    );
    return J.asString(J.asMap(data)['id']);
  }
}

/// Provider for [BookingDetailActions].
final bookingDetailActionsProvider = Provider<BookingDetailActions>((ref) {
  return BookingDetailActions(ref.watch(apiClientProvider));
});
