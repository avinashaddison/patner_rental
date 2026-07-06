import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';

/// Centered loading spinner with an optional message. For list/grid skeletons
/// use [ShimmerBox] / [CompanionCardSkeleton].
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.6),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A shimmering placeholder box for skeleton loaders.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppSpacing.radiusSm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.darkField : const Color(0xFFE9E7EF),
      highlightColor: isDark ? AppColors.darkLine : const Color(0xFFF5F4F8),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Skeleton card matching the companion card footprint, for grid loaders.
class CompanionCardSkeleton extends StatelessWidget {
  const CompanionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Mirrors the FeaturedCompanionCard footprint: 1.15 photo + body + footer.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          AspectRatio(
            aspectRatio: 1.15,
            child: ShimmerBox(height: double.infinity),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerBox(width: 110, height: 15),
                SizedBox(height: 8),
                ShimmerBox(width: 70, height: 12),
                SizedBox(height: 10),
                ShimmerBox(width: 60, height: 18),
              ],
            ),
          ),
          ShimmerBox(width: double.infinity, height: 48),
        ],
      ),
    );
  }
}
