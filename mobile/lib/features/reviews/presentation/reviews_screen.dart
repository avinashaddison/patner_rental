import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/reviews/application/reviews_controller.dart';
import 'package:companion_ranchi/features/reviews/presentation/widgets/review_card.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Full, paginated reviews for a companion
/// (`GET /reviews/companion/:companionId`). Shows an aggregate rating summary
/// plus each review with its three sub-ratings.
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key, required this.companionId});

  final String companionId;

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(reviewsControllerProvider(widget.companionId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewsControllerProvider(widget.companionId));
    final notifier =
        ref.read(reviewsControllerProvider(widget.companionId).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: _buildBody(state, notifier),
    );
  }

  Widget _buildBody(ReviewsState state, ReviewsController notifier) {
    if (state.isLoading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          ShimmerBox(height: 150, radius: AppSpacing.radius),
          SizedBox(height: AppSpacing.lg),
          ShimmerBox(height: 120, radius: AppSpacing.radius),
          SizedBox(height: AppSpacing.md),
          ShimmerBox(height: 120, radius: AppSpacing.radius),
        ],
      );
    }

    if (state.error != null) {
      return ErrorView(error: state.error, onRetry: notifier.load);
    }

    if (state.reviews.isEmpty) {
      return const EmptyView(
        icon: Icons.reviews_outlined,
        title: 'No reviews yet',
        message:
            'This companion has not received any reviews yet. Reviews appear '
            'after completed bookings.',
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.load,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: state.reviews.length + 2, // header + footer
        separatorBuilder: (_, i) =>
            const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _RatingSummary(
              breakdown: state.breakdown,
              total: state.total,
            );
          }
          final reviewIndex = i - 1;
          if (reviewIndex >= state.reviews.length) {
            // Footer: paging spinner or end-of-list spacer.
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: state.isLoadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox(height: AppSpacing.lg),
            );
          }
          return ReviewCard(
            review: state.reviews[reviewIndex],
            showSubRatings: true,
          );
        },
      ),
    );
  }
}

/// Aggregate rating summary: big average, total count, and per-star bars.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.breakdown, required this.total});

  final RatingBreakdown breakdown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      breakdown.average.toStringAsFixed(1),
                      maxLines: 1,
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  StarRow(rating: breakdown.average, size: 16),
                  const SizedBox(height: 4),
                  Text(
                    total == 1 ? '1 review' : '$total reviews',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                children: [
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _BreakdownBar(
                        star: star,
                        fraction: breakdown.fractionFor(star),
                        count: breakdown.countFor(star),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.star,
    required this.fraction,
    required this.count,
  });

  final int star;
  final double fraction;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            '$star',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.star_rounded, size: 13, color: AppColors.star),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppColors.line,
              valueColor: const AlwaysStoppedAnimation(AppColors.star),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 22,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}
