import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// The active search/filter criteria for `GET /companions`. Immutable; mutate
/// via [copyWith]. Empty/null fields are simply omitted from the query.
class CompanionSearchFilters {
  const CompanionSearchFilters({
    this.query,
    this.category,
    this.city,
    this.minRate,
    this.maxRate,
    this.minRating,
    this.onlineOnly = false,
    this.featuredOnly = false,
    this.sort,
  });

  /// Free-text query (`q`).
  final String? query;

  /// Category slug, e.g. `coffee-partner`.
  final String? category;
  final String? city;

  /// Rate bounds in INR.
  final double? minRate;
  final double? maxRate;

  /// Minimum average rating (0..5).
  final double? minRating;
  final bool onlineOnly;
  final bool featuredOnly;

  /// e.g. `rating:desc`, `hourlyRate:asc`.
  final String? sort;

  /// Whether any non-default filter is active (used to show a "clear" affordance).
  bool get hasActiveFilters =>
      (query != null && query!.trim().isNotEmpty) ||
      category != null ||
      city != null ||
      minRate != null ||
      maxRate != null ||
      minRating != null ||
      onlineOnly ||
      featuredOnly ||
      sort != null;

  Map<String, dynamic> toQuery({required int page, required int limit}) {
    final q = <String, dynamic>{'page': page, 'limit': limit};
    if (query != null && query!.trim().isNotEmpty) q['q'] = query!.trim();
    if (category != null) q['category'] = category;
    if (city != null) q['city'] = city;
    if (minRate != null) q['minRate'] = minRate;
    if (maxRate != null) q['maxRate'] = maxRate;
    if (minRating != null) q['minRating'] = minRating;
    if (onlineOnly) q['online'] = true;
    if (featuredOnly) q['featured'] = true;
    if (sort != null) q['sort'] = sort;
    return q;
  }

  CompanionSearchFilters copyWith({
    String? query,
    Object? category = _sentinel,
    Object? city = _sentinel,
    Object? minRate = _sentinel,
    Object? maxRate = _sentinel,
    Object? minRating = _sentinel,
    bool? onlineOnly,
    bool? featuredOnly,
    Object? sort = _sentinel,
  }) {
    return CompanionSearchFilters(
      query: query ?? this.query,
      category: category == _sentinel ? this.category : category as String?,
      city: city == _sentinel ? this.city : city as String?,
      minRate: minRate == _sentinel ? this.minRate : minRate as double?,
      maxRate: maxRate == _sentinel ? this.maxRate : maxRate as double?,
      minRating:
          minRating == _sentinel ? this.minRating : minRating as double?,
      onlineOnly: onlineOnly ?? this.onlineOnly,
      featuredOnly: featuredOnly ?? this.featuredOnly,
      sort: sort == _sentinel ? this.sort : sort as String?,
    );
  }

  static const Object _sentinel = Object();
}

/// A page of companion results with pagination metadata from the API envelope.
class CompanionSearchResult {
  const CompanionSearchResult({
    required this.companions,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<CompanionModel> companions;
  final int page;
  final int limit;
  final int total;

  /// True when more pages are available given `page`, `limit` and `total`.
  bool get hasMore => companions.length >= limit && page * limit < total;
}

/// Data access for searching/listing companions (`GET /companions`).
class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  Future<CompanionSearchResult> search(
    CompanionSearchFilters filters, {
    int page = 1,
    int limit = 20,
  }) async {
    final envelope = await _api.getEnvelope(
      '/companions',
      query: filters.toQuery(page: page, limit: limit),
    );

    final data = envelope['data'];
    final list = data is List
        ? data
        : (data is Map && data['companions'] is List
            ? data['companions'] as List
            : const []);
    final companions = J
        .asMapList(list)
        .map(CompanionModel.fromJson)
        .toList(growable: false);

    final meta = envelope['meta'] is Map
        ? Map<String, dynamic>.from(envelope['meta'] as Map)
        : const <String, dynamic>{};

    return CompanionSearchResult(
      companions: companions,
      page: J.asInt(meta['page'], page),
      limit: J.asInt(meta['limit'], limit),
      total: J.asInt(meta['total'], companions.length),
    );
  }
}

/// Provider for [SearchRepository].
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(apiClientProvider));
});
