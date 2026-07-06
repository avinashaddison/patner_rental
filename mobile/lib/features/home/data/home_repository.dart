import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/category_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/network/api_client.dart';

/// Data access for the discovery **home** screen. Talks to the companion
/// endpoints from API.md (`/companions/featured`, `/companions/popular-nearby`,
/// `/companions/categories`) and maps the responses to [CompanionModel] /
/// [CategoryModel].
class HomeRepository {
  HomeRepository(this._api);

  final ApiClient _api;

  /// `GET /companions/categories` → fixed activity category list.
  Future<List<CategoryModel>> fetchCategories() async {
    final data = await _api.getJson('/companions/categories');
    return _mapCategories(data);
  }

  /// `GET /companions/featured` → featured companion cards. Optionally filtered
  /// by [city].
  Future<List<CompanionModel>> fetchFeatured({String? city}) async {
    final data = await _api.getJson(
      '/companions/featured',
      query: {
        'limit': 10,
        if (city != null && city.isNotEmpty) 'city': city,
      },
    );
    return _mapCompanions(data);
  }

  /// `GET /companions/popular-nearby?lat&lng&city` → location-aware popular
  /// cards. Latitude/longitude and city are optional; when absent the backend
  /// returns the broader set.
  Future<List<CompanionModel>> fetchPopularNearby({
    double? lat,
    double? lng,
    String? city,
  }) async {
    final data = await _api.getJson(
      '/companions/popular-nearby',
      query: {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (city != null && city.isNotEmpty) 'city': city,
        'limit': 20,
      },
    );
    return _mapCompanions(data);
  }

  List<CategoryModel> _mapCategories(dynamic data) {
    final list = data is List
        ? data
        : (data is Map && data['categories'] is List
            ? data['categories'] as List
            : const []);
    return J
        .asMapList(list)
        .map(CategoryModel.fromJson)
        .toList(growable: false);
  }

  List<CompanionModel> _mapCompanions(dynamic data) {
    // Endpoints may return a bare list or `{ companions: [...] }`.
    final list = data is List
        ? data
        : (data is Map && data['companions'] is List
            ? data['companions'] as List
            : const []);
    return J
        .asMapList(list)
        .map(CompanionModel.fromJson)
        .toList(growable: false);
  }
}

/// Provider for [HomeRepository], wired to the shared [apiClientProvider].
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(apiClientProvider));
});
