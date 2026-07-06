import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/shared/widgets/online_dot.dart';
import 'package:companion_ranchi/shared/widgets/rating_stars.dart';
import 'package:companion_ranchi/shared/widgets/verified_badge.dart';

/// Premium marketplace card for a [CompanionModel] (Airbnb/Bumble inspired):
/// large photo with a dark scrim, verified + online badges, rating, rate.
///
/// Two layouts:
///  * [CompanionCard] — vertical, for grids and horizontal rails.
///  * [CompanionListTile] — horizontal, for search result lists.
class CompanionCard extends StatelessWidget {
  const CompanionCard({
    super.key,
    required this.companion,
    this.onTap,
    this.width,
    this.aspectRatio = 0.78,
  });

  final CompanionModel companion;
  final VoidCallback? onTap;

  /// Fixed width for horizontal rails; null = fill the parent (grid).
  final double? width;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Photo(url: companion.primaryPhotoUrl),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.photoScrim),
            ),
            // Top badges
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  if (companion.isFeatured) const _FeaturedBadge(),
                  const Spacer(),
                  if (companion.isOnline)
                    const OnlineDot(isOnline: true, size: 12),
                ],
              ),
            ),
            // Bottom info
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          companion.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (companion.isVerified) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(compact: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 15, color: AppColors.star),
                      const SizedBox(width: 2),
                      Text(
                        companion.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          companion.distanceKm != null
                              ? Formatters.distance(companion.distanceKm)
                              : companion.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      Formatters.ratePerHour(companion.hourlyRate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: card,
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}

/// Horizontal companion row for search results.
class CompanionListTile extends StatelessWidget {
  const CompanionListTile({
    super.key,
    required this.companion,
    this.onTap,
  });

  final CompanionModel companion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: _Photo(url: companion.primaryPhotoUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            companion.age != null
                                ? '${companion.name}, ${companion.age}'
                                : companion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (companion.isVerified) ...[
                          const SizedBox(width: 6),
                          const VerifiedBadge(compact: true),
                        ],
                        if (companion.isOnline) ...[
                          const SizedBox(width: 6),
                          const OnlineDot(isOnline: true, withBorder: false),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    RatingStars(
                      rating: companion.rating,
                      count: companion.ratingCount,
                      size: 14,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            companion.distanceKm != null
                                ? Formatters.distance(companion.distanceKm)
                                : companion.city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.money(companion.hourlyRate),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  Text('per hour', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const _PhotoPlaceholder();
    }
    // Cap decode at screen-width pixels — card photos are otherwise decoded at
    // full source resolution (1080×1500+), causing scroll jank in grids/lists.
    final int decodeW = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      memCacheWidth: decodeW,
      maxWidthDiskCache: decodeW,
      placeholder: (_, __) => const ColoredBox(color: AppColors.field),
      errorWidget: (_, __, ___) => const _PhotoPlaceholder(),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.card),
      child: Center(
        child: Icon(Icons.person_rounded, size: 48, color: Colors.white70),
      ),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  const _FeaturedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded,
              size: 13, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'Featured',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
