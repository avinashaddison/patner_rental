import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/search/data/search_repository.dart';

/// Immutable UI state for the search screen: the current [filters], the
/// accumulated [companions], loading/paging flags and any error.
class SearchState {
  const SearchState({
    this.filters = const CompanionSearchFilters(),
    this.companions = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.page = 1,
    this.total = 0,
    this.hasMore = false,
    this.hasSearched = false,
  });

  final CompanionSearchFilters filters;
  final List<CompanionModel> companions;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;
  final int page;
  final int total;
  final bool hasMore;

  /// True once at least one query has completed (drives the empty-state copy).
  final bool hasSearched;

  SearchState copyWith({
    CompanionSearchFilters? filters,
    List<CompanionModel>? companions,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    int? page,
    int? total,
    bool? hasMore,
    bool? hasSearched,
  }) {
    return SearchState(
      filters: filters ?? this.filters,
      companions: companions ?? this.companions,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error == _sentinel ? this.error : error,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }

  static const Object _sentinel = Object();
}

/// Drives companion search with debounce-friendly explicit triggers and
/// infinite-scroll pagination.
class SearchController extends AutoDisposeNotifier<SearchState> {
  static const int _pageSize = 20;

  SearchRepository get _repo => ref.read(searchRepositoryProvider);

  @override
  SearchState build() => const SearchState();

  /// Replace the whole filter set and run a fresh search from page 1.
  Future<void> applyFilters(CompanionSearchFilters filters) async {
    state = state.copyWith(filters: filters);
    await search();
  }

  /// Update just the free-text query, then search.
  Future<void> setQuery(String query) async {
    state = state.copyWith(filters: state.filters.copyWith(query: query));
    await search();
  }

  /// Filter by a single category slug (used by category chips), then search.
  Future<void> setCategory(String? slug) async {
    state = state.copyWith(filters: state.filters.copyWith(category: slug));
    await search();
  }

  /// Clear all filters and results.
  Future<void> clear() async {
    state = const SearchState();
    await search();
  }

  /// Run the first page for the current filters.
  Future<void> search() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      page: 1,
    );
    try {
      final result = await _repo.search(
        state.filters,
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

  /// Fetch and append the next page (infinite scroll). No-op when already
  /// loading or no more results.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.page + 1;
    try {
      final result = await _repo.search(
        state.filters,
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
      // Keep existing results; surface a non-blocking failure by stopping.
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }
}

final searchControllerProvider =
    AutoDisposeNotifierProvider<SearchController, SearchState>(
  SearchController.new,
);
