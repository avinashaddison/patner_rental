import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/features/search/application/search_controller.dart';
import 'package:companion_ranchi/features/search/data/search_repository.dart';

/// Argument bundle for the category listing: the slug plus an optional sort.
class CategoryListingArgs {
  const CategoryListingArgs({required this.slug, this.sort});

  final String slug;
  final String? sort;

  @override
  bool operator ==(Object other) =>
      other is CategoryListingArgs &&
      other.slug == slug &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(slug, sort);
}

/// Paginated companion listing for a single category slug. Reuses
/// [SearchController]'s state shape and the shared [SearchRepository], so the
/// category page behaves like a pre-filtered search.
class CategoryListingController
    extends AutoDisposeFamilyNotifier<SearchState, CategoryListingArgs> {
  static const int _pageSize = 20;

  SearchRepository get _repo => ref.read(searchRepositoryProvider);

  CompanionSearchFilters _filtersFor(CategoryListingArgs args) =>
      CompanionSearchFilters(category: args.slug, sort: args.sort);

  @override
  SearchState build(CategoryListingArgs arg) {
    // Auto-load the first page.
    Future.microtask(load);
    return SearchState(filters: _filtersFor(arg), isLoading: true);
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null, page: 1);
    try {
      final result = await _repo.search(
        _filtersFor(arg),
        page: 1,
        limit: _pageSize,
      );
      state = state.copyWith(
        companions: result.companions,
        isLoading: false,
        page: result.page,
        total: result.total,
        hasMore: result.hasMore,
        hasSearched: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e,
        companions: const [],
        hasSearched: true,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.page + 1;
    try {
      final result = await _repo.search(
        _filtersFor(arg),
        page: nextPage,
        limit: _pageSize,
      );
      state = state.copyWith(
        companions: [...state.companions, ...result.companions],
        isLoadingMore: false,
        page: result.page,
        total: result.total,
        hasMore: result.hasMore,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }
}

final categoryListingControllerProvider = AutoDisposeNotifierProviderFamily<
    CategoryListingController, SearchState, CategoryListingArgs>(
  CategoryListingController.new,
);
