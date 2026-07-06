import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/shared/widgets/rating_stars.dart';
import 'package:companion_ranchi/shared/widgets/user_avatar.dart';

/// A single review card: reviewer avatar + name, overall star row, relative
/// date, optional comment and — when [showSubRatings] is true — the three
/// sub-ratings (behaviour, communication, punctuality).
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.review,
    this.showSubRatings = false,
  });

  final ReviewModel review;
  final bool showSubRatings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  photoUrl: review.customerPhotoUrl,
                  name: review.customerName ?? 'Customer',
                  radius: 20,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.customerName ?? 'Customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          StarRow(rating: review.overallRating, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            review.overallRating.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (review.createdAt != null)
                  Text(
                    Formatters.relative(review.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
              ],
            ),
            if (review.comment != null && review.comment!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                review.comment!.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
            if (showSubRatings) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _SubRating(label: 'Behaviour', value: review.behaviourRating),
                  _SubRating(
                      label: 'Communication',
                      value: review.communicationRating),
                  _SubRating(
                      label: 'Punctuality', value: review.punctualityRating),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubRating extends StatelessWidget {
  const _SubRating({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.inkMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        RatingStars(
          rating: value.toDouble(),
          size: 13,
          showValue: false,
        ),
      ],
    );
  }
}
