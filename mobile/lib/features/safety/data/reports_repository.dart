import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_client.dart';

/// Data access for the trust-and-safety reporting flow (`POST /reports`).
///
/// Lets a signed-in user file a complaint against another user, optionally tied
/// to a booking. Reports land in the admin moderation queue.
class ReportsRepository {
  ReportsRepository(this._api);

  final ApiClient _api;

  /// `POST /reports` — file a complaint against [reportedUserId].
  ///
  /// [category] must be one of the backend `ReportCategory` values
  /// (HARASSMENT, FAKE_PROFILE, ABUSE, SPAM, OTHER).
  Future<void> createReport({
    required String reportedUserId,
    required String category,
    String? description,
    String? bookingId,
  }) async {
    await _api.postJson(
      '/reports',
      body: {
        'reportedUserId': reportedUserId,
        'category': category,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (bookingId != null) 'bookingId': bookingId,
      },
    );
  }
}

/// App-wide [ReportsRepository] provider, wired to the shared [ApiClient].
final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(apiClientProvider));
});
