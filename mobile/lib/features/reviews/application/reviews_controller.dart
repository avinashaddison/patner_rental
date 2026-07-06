import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/features/reviews/data/reviews_repository.dart';

/// Aggregate distribution of overall ratings (5★ down to 1★) used to render the
/// rating summary bars.
class RatingBreakdown {
  const RatingBreakdown(this.counts, this.total, this.average);

  /// Index 0 = 1★ … index 4 = 5★.
  final List<int> counts;
  final int total;
  final double average;

  int countFor(int star) =>
      (star >= 1 && star <= 5) ? counts[star - 1] : 0;

  double fractionFor(int star) =>
      total == 0 ? 0 : countFor(star) / total;

  static RatingBreakdown from(List<ReviewModel> reviews) {
    final counts = List<int>.filled(5, 0);
    var sum = 0.0;
    for (final r in reviews) {
      final rounded = r.overallRating.round().clamp(1, 5);
      counts[rounded - 1]++;
      sum += r.overallRating;
    }
    final avg = reviews.isEmpty ? 0.0 : sum / reviews.length;
    return RatingBreakdown(counts, reviews.length, avg);
  }
}

/// Immutable state for the reviews screen with infinite-scroll pagination.
class ReviewsState {
  const ReviewsState({
    this.reviews = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.page = 1,
    this.total = 0,
    this.hasMore = false,
  });

  final List<ReviewModel> reviews;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;
  final int page;
  final int total;
  final bool hasMore;

  /// Distribution over the loaded reviews (for the summary bars).
  RatingBreakdown get breakdown => RatingBreakdown.from(reviews);

  ReviewsState copyWith({
    List<ReviewModel>? reviews,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    int? page,
    int? total,
    bool? hasMore,
  }) {
    return ReviewsState(
      reviews: reviews ?? this.reviews,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error == _sentinel ? this.error : error,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  static const Object _sentinel = Object();
}

/// Loads and paginates a companion's reviews. Keyed by companion id.
class ReviewsController
    extends AutoDisposeFamilyNotifier<ReviewsState, String> {
  static const int _pageSize = 15;

  ReviewsRepository get _repo => ref.read(reviewsRepositoryProvider);

  @override
  ReviewsState build(String companionId) {
    Future.microtask(load);
    return const ReviewsState();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null, page: 1);
    try {
      final result = await _repo.fetch(arg, page: 1, limit: _pageSize);
      state = state.copyWith(
        reviews: result.reviews,
        isLoading: false,
        page: result.page,
        total: result.total,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e,
        reviews: const [],
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.page + 1;
    try {
      final result = await _repo.fetch(arg, page: nextPage, limit: _pageSize);
      state = state.copyWith(
        reviews: [...state.reviews, ...result.reviews],
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

final reviewsControllerProvider =
    AutoDisposeNotifierProviderFamily<ReviewsController, ReviewsState, String>(
  ReviewsController.new,
);
