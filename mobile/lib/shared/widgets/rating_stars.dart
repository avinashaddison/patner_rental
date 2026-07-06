import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Compact, read-only star rating with an optional numeric value and count.
/// For interactive rating input use `flutter_rating_bar` directly in the
/// reviews feature.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.count,
    this.size = 16,
    this.showValue = true,
    this.color = AppColors.star,
  });

  /// 0..5 rating.
  final double rating;

  /// Optional number of ratings shown in parentheses.
  final int? count;
  final double size;
  final bool showValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 2, color: color),
        if (showValue) ...[
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size - 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (count != null) ...[
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: TextStyle(fontSize: size - 3, color: muted),
          ),
        ],
      ],
    );
  }
}

/// A row of five outline/filled stars (no number), for review cards.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.rating,
    this.size = 16,
    this.color = AppColors.star,
  });

  final double rating;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? color : color.withValues(alpha: 0.4),
        );
      }),
    );
  }
}
