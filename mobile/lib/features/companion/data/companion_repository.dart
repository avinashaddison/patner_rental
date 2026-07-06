import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// Data access for a single companion's **full profile**
/// (`GET /companions/:id`) plus a short reviews preview
/// (`GET /companions/:id/reviews`).
class CompanionRepository {
  CompanionRepository(this._api);

  final ApiClient _api;

  /// Full profile: photos, languages, interests, about, rate, rating,
  /// verification, categories, availability and any embedded reviews.
  Future<CompanionModel> fetchProfile(String id) async {
    final data = await _api.getJson('/companions/$id');
    final map = data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
    // Some backends nest the profile under `companion`.
    final json = map['companion'] is Map
        ? Map<String, dynamic>.from(map['companion'] as Map)
        : map;
    return CompanionModel.fromJson(json);
  }

  /// A small preview slice of the most recent reviews for the profile screen.
  Future<List<ReviewModel>> fetchReviewsPreview(String id,
      {int limit = 3}) async {
    final data = await _api.getJson(
      '/companions/$id/reviews',
      query: {'page': 1, 'limit': limit, 'sort': 'createdAt:desc'},
    );
    final list = data is List
        ? data
        : (data is Map && data['reviews'] is List
            ? data['reviews'] as List
            : const []);
    return J
        .asMapList(list)
        .map(ReviewModel.fromJson)
        .toList(growable: false);
  }
}

final companionRepositoryProvider = Provider<CompanionRepository>((ref) {
  return CompanionRepository(ref.watch(apiClientProvider));
});
