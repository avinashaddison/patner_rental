import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// A page of reviews plus pagination metadata from the API envelope.
class ReviewsPage {
  const ReviewsPage({
    required this.reviews,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<ReviewModel> reviews;
  final int page;
  final int limit;
  final int total;

  bool get hasMore => reviews.length >= limit && page * limit < total;
}

/// Data access for a companion's paginated reviews
/// (`GET /reviews/companion/:companionId`).
class ReviewsRepository {
  ReviewsRepository(this._api);

  final ApiClient _api;

  Future<ReviewsPage> fetch(
    String companionId, {
    int page = 1,
    int limit = 15,
  }) async {
    final envelope = await _api.getEnvelope(
      '/reviews/companion/$companionId',
      query: {'page': page, 'limit': limit, 'sort': 'createdAt:desc'},
    );

    final data = envelope['data'];
    final list = data is List
        ? data
        : (data is Map && data['reviews'] is List
            ? data['reviews'] as List
            : const []);
    final reviews = J
        .asMapList(list)
        .map(ReviewModel.fromJson)
        .toList(growable: false);

    final meta = envelope['meta'] is Map
        ? Map<String, dynamic>.from(envelope['meta'] as Map)
        : const <String, dynamic>{};

    return ReviewsPage(
      reviews: reviews,
      page: J.asInt(meta['page'], page),
      limit: J.asInt(meta['limit'], limit),
      total: J.asInt(meta['total'], reviews.length),
    );
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(ref.watch(apiClientProvider));
});
