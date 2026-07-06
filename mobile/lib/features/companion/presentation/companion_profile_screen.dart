import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/models/review_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/chat/data/chat_repository.dart';
import 'package:companion_ranchi/features/companion/application/companion_providers.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';
import 'package:companion_ranchi/features/reviews/presentation/widgets/review_card.dart';
import 'package:companion_ranchi/features/safety/presentation/safety_actions.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Full companion profile (`GET /companions/:id`): an immersive, dating-app
/// style photo hero with an overlaid identity card, a collapsing app bar that
/// reveals the name on scroll, Follow / Message actions, stats, safety, the
/// activities / about / languages / interests sections, a posts grid, a reviews
/// summary and a sticky Book / Message CTA bar.
class CompanionProfileScreen extends ConsumerWidget {
  const CompanionProfileScreen({super.key, required this.companionId});

  final String companionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companionProfileProvider(companionId));

    return Scaffold(
      body: async.when(
        loading: () => const _ProfileLoading(),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            error: e,
            onRetry: () =>
                ref.invalidate(companionProfileProvider(companionId)),
          ),
        ),
        data: (companion) => _ProfileBody(companion: companion),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (companion) => _BookBar(companion: companion),
        orElse: () => null,
      ),
    );
  }
}

/// Resolve the ordered list of photo URLs (primary first, de-duplicated).
List<String> _photoUrls(CompanionModel c) {
  final urls = <String>[];
  final primary = c.primaryPhotoUrl;
  if (primary != null && primary.isNotEmpty) urls.add(primary);
  for (final p in c.photos) {
    if (p.photoUrl.isNotEmpty && !urls.contains(p.photoUrl)) {
      urls.add(p.photoUrl);
    }
  }
  return urls;
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photos = _photoUrls(companion);
    final screenH = MediaQuery.sizeOf(context).height;
    final expandedHeight = (screenH * 0.6).clamp(440.0, 580.0);
    final isOwn = ref.watch(currentUserProvider)?.id == companion.userId;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: expandedHeight,
          pinned: true,
          stretch: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          leading: const _CircleIconButton(icon: Icons.arrow_back_rounded),
          actions: [
            if (companion.userId != null && !isOwn)
              CircleSafetyButton(
                userId: companion.userId!,
                name: companion.name,
              ),
            const SizedBox(width: 4),
          ],
          flexibleSpace: _Hero(
            companion: companion,
            photos: photos,
            expandedHeight: expandedHeight,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FollowBar(companion: companion),
                _StatsRow(companion: companion),
                const SizedBox(height: AppSpacing.lg),
                const SafetyBanner(),
                if (companion.categories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Activities',
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final slug in companion.categories)
                          _Pill(
                            label: AppCategories.nameFor(slug),
                            emoji: AppCategories.bySlug(slug)?.emoji,
                          ),
                      ],
                    ),
                  ),
                ],
                if (companion.aboutMe != null &&
                    companion.aboutMe!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _AboutCard(
                    name: companion.name,
                    about: companion.aboutMe!.trim(),
                  ),
                ],
                if (companion.languages.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Languages',
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final lang in companion.languages)
                          _Pill(label: lang, icon: Icons.translate_rounded),
                      ],
                    ),
                  ),
                ],
                if (companion.interests.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: '✨ Interests',
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final interest in companion.interests)
                          _InterestTile(label: interest),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _PostsSection(companion: companion),
                const SizedBox(height: AppSpacing.lg),
                _ReviewsSection(companion: companion),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Immersive photo hero with overlaid identity + collapse-revealed title.
// ---------------------------------------------------------------------------

class _Hero extends StatefulWidget {
  const _Hero({
    required this.companion,
    required this.photos,
    required this.expandedHeight,
  });

  final CompanionModel companion;
  final List<String> photos;
  final double expandedHeight;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final maxExtent = widget.expandedHeight;
    final minExtent = kToolbarHeight + topPad;
    final photos = widget.photos;

    return LayoutBuilder(
      builder: (context, constraints) {
        final range = (maxExtent - minExtent).clamp(1.0, double.infinity);
        final t = ((maxExtent - constraints.maxHeight) / range).clamp(0.0, 1.0);
        final overlayOpacity = (1 - t / 0.55).clamp(0.0, 1.0);
        final collapsedOpacity = ((t - 0.5) / 0.5).clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Photo carousel.
            if (photos.isEmpty)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.card),
                child: Center(
                  child: Icon(Icons.person_rounded,
                      size: 88, color: Colors.white70),
                ),
              )
            else
              PageView.builder(
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => CachedNetworkImage(
                  imageUrl: photos[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const ColoredBox(color: AppColors.field),
                  errorWidget: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(gradient: AppGradients.card),
                    child: Center(
                      child: Icon(Icons.person_rounded,
                          size: 88, color: Colors.white70),
                    ),
                  ),
                ),
              ),

            // Top scrim — keeps the status bar + controls legible.
            const IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 150,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x73000000), Color(0x00000000)],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // Bottom scrim — keeps the overlaid identity legible.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xE6000000)],
                  ),
                ),
              ),
            ),

            // Overlaid identity card (fades out as the bar collapses).
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: IgnorePointer(
                child: Opacity(
                  opacity: overlayOpacity,
                  child: _HeroIdentity(
                    companion: widget.companion,
                    photoIndex: _index,
                    photoCount: photos.length,
                  ),
                ),
              ),
            ),

            // Collapsed solid bar with the name (fades in as it collapses).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: minExtent,
              child: IgnorePointer(
                child: Opacity(
                  opacity: collapsedOpacity,
                  child: _CollapsedBar(
                    companion: widget.companion,
                    topPad: topPad,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// White-on-photo identity block: photo dots, name + age, verification,
/// location / availability, and a row of quick info chips.
class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({
    required this.companion,
    required this.photoIndex,
    required this.photoCount,
  });

  final CompanionModel companion;
  final int photoIndex;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final title = companion.age != null
        ? '${companion.name}, ${companion.age}'
        : companion.name;
    final languages = companion.languages.take(2).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Featured gradient pill (left) + photo counter (right), mock-style.
        if (companion.isFeatured || photoCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                if (companion.isFeatured)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4D6D), Color(0xFFFF9A5A)],
                      ),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF4D6D)
                              .withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Featured',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (photoCount > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          '${photoIndex + 1}/$photoCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(color: Color(0x66000000), blurRadius: 8),
                  ],
                ),
              ),
            ),
            if (companion.isVerified) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified_rounded,
                  color: Colors.white, size: 24),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.place_rounded, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              companion.city,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: companion.isOnline ? AppColors.online : Colors.white60,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              companion.isOnline ? 'Online now' : 'Offline',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (companion.ratingCount > 0)
              _HeroChip(
                icon: Icons.star_rounded,
                iconColor: AppColors.star,
                label:
                    '${companion.rating.toStringAsFixed(1)} (${companion.ratingCount})',
              ),
            if (languages.isNotEmpty)
              _HeroChip(
                icon: Icons.translate_rounded,
                iconColor: const Color(0xFFFF6FA0),
                label: languages,
              ),
            if (companion.isVerified)
              const _HeroChip(
                icon: Icons.verified_user_rounded,
                iconColor: Color(0xFF9C6BFF),
                label: 'ID Verified',
              ),
            if (companion.distanceKm != null)
              _HeroChip(
                icon: Icons.near_me_rounded,
                iconColor: const Color(0xFF64B5F6),
                label: '${companion.distanceKm!.toStringAsFixed(1)} km away',
              )
            else
              const _HeroChip(
                icon: Icons.shield_rounded,
                iconColor: Color(0xFFFF4D6D),
                label: 'Public meetups only',
              ),
          ],
        ),
      ],
    );
  }
}

/// A frosted translucent chip used over the photo hero.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid header revealed as the app bar collapses: mini avatar + name.
class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({required this.companion, required this.topPad});

  final CompanionModel companion;
  final double topPad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: EdgeInsets.only(top: topPad, left: 60, right: 60),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          UserAvatar(
            photoUrl: companion.primaryPhotoUrl,
            name: companion.name,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              companion.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (companion.isVerified) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified_rounded,
                color: AppColors.verified, size: 18),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats, sections, pills.
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Row(
        children: [
          _Stat(
            icon: Icons.star_rounded,
            iconColor: AppColors.star,
            value: companion.ratingCount > 0
                ? companion.rating.toStringAsFixed(1)
                : 'New',
            label: companion.ratingCount > 0
                ? '${companion.ratingCount} reviews'
                : 'no reviews yet',
          ),
          _divider(),
          // "0 bookings" beside dozens of reviews reads as fake — show "New"
          // until there's a real count.
          _Stat(
            icon: Icons.event_available_rounded,
            iconColor: AppColors.primary,
            value: companion.totalBookings > 0
                ? '${companion.totalBookings}'
                : 'New',
            label: companion.totalBookings > 0 ? 'Bookings' : 'companion',
          ),
          _divider(),
          _Stat(
            icon: Icons.payments_rounded,
            iconColor: AppColors.success,
            value: '₹${companion.hourlyRate.toStringAsFixed(0)}',
            label: 'per hour',
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: AppColors.line,
      );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            // Tinted icon disc (mock style) instead of a bare icon.
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 19),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 6),
            // Pink accent underline (mock detail).
            Container(
              width: 26,
              height: 3.5,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft pink "About {first name}" card: quote mark, bio (collapsed to 3 lines
/// with a View More toggle when longer) and a decorative heart wash.
class _AboutCard extends StatefulWidget {
  const _AboutCard({required this.name, required this.about});

  final String name;
  final String about;

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final firstName = widget.name.trim().split(RegExp(r'\s+')).first;
    final isLong = widget.about.length > 120;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Stack(
        children: [
          // Decorative heart wash, top-right.
          Positioned(
            top: -6,
            right: -6,
            child: Icon(
              Icons.favorite_rounded,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_quote_rounded,
                      color: AppColors.primary, size: 26),
                  const SizedBox(width: 6),
                  Text(
                    'About $firstName',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.about,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.55, color: AppColors.ink),
              ),
              if (isLong) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      border: Border.all(color: AppColors.fieldBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? 'View Less' : 'View More',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Colourful interest tile: tinted rounded square with a matching icon on top
/// and the label beneath (mock style). Colours/icons keyed by interest name.
class _InterestTile extends StatelessWidget {
  const _InterestTile({required this.label});

  final String label;

  static const Map<String, (IconData, Color)> _style = {
    'Music': (Icons.music_note_rounded, Color(0xFFFF4D6D)),
    'Movies': (Icons.movie_rounded, Color(0xFFE53935)),
    'Food': (Icons.restaurant_rounded, Color(0xFFFF8F3C)),
    'Travel': (Icons.flight_takeoff_rounded, Color(0xFF2196F3)),
    'Fitness': (Icons.fitness_center_rounded, Color(0xFF22A85B)),
    'Reading': (Icons.menu_book_rounded, Color(0xFF00897B)),
    'Photography': (Icons.photo_camera_rounded, Color(0xFF7C3AED)),
    'Art': (Icons.palette_rounded, Color(0xFF9C27B0)),
    'Sports': (Icons.sports_soccer_rounded, Color(0xFF43A047)),
    'Gaming': (Icons.sports_esports_rounded, Color(0xFF3F51B5)),
    'Fashion': (Icons.checkroom_rounded, Color(0xFFEC407A)),
    'Technology': (Icons.memory_rounded, Color(0xFF546E7A)),
    'Cooking': (Icons.soup_kitchen_rounded, Color(0xFFF4511E)),
    'Dancing': (Icons.nightlife_rounded, Color(0xFFAB47BC)),
    'Coffee': (Icons.local_cafe_rounded, Color(0xFF8D6E63)),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) =
        _style[label] ?? (Icons.interests_rounded, AppColors.primary);
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.emoji, this.icon});

  final String label;
  final String? emoji;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkField : AppColors.field,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: isDark ? AppColors.darkLine : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Full-width Follow / Following toggle + a follower count. Hidden on your own
/// profile. Manages optimistic local state so the tap feels instant.
class _FollowBar extends ConsumerStatefulWidget {
  const _FollowBar({required this.companion});

  final CompanionModel companion;

  @override
  ConsumerState<_FollowBar> createState() => _FollowBarState();
}

class _FollowBarState extends ConsumerState<_FollowBar> {
  late bool _following = widget.companion.isFollowing;
  late int _followers = widget.companion.followerCount;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final repo = ref.read(feedRepositoryProvider);
    final was = _following;
    setState(() {
      _following = !was;
      _followers += was ? -1 : 1;
      _busy = true;
    });
    try {
      final r = was
          ? await repo.unfollow(widget.companion.id)
          : await repo.follow(widget.companion.id);
      if (mounted) {
        setState(() {
          _following = r.following;
          _followers = r.followerCount;
        });
      }
      // Refresh the Following/Explore tabs (not this profile — local state is live).
      ref.invalidate(feedProvider);
      ref.invalidate(exploreProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _following = was;
        _followers += was ? 1 : -1;
      });
      final msg = e is ApiException ? e.message : 'Could not update follow.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(currentUserProvider)?.id;
    final isOwn = myUserId != null && myUserId == widget.companion.userId;
    if (isOwn) return const SizedBox(height: AppSpacing.xs);

    // One white action card: gradient Follow | live follower count | Message.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.fieldBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _busy ? null : _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: _following ? null : AppGradients.primary,
                    color: _following
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : null,
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _following
                            ? Icons.check_rounded
                            : Icons.person_add_alt_1_rounded,
                        size: 18,
                        color:
                            _following ? AppColors.primary : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _following ? 'Following' : 'Follow',
                        style: TextStyle(
                          color:
                              _following ? AppColors.primary : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_followers',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    'Followers',
                    style:
                        TextStyle(color: AppColors.inkMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 3),
                      Text(
                        '${widget.companion.totalLikes}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Likes',
                    style:
                        TextStyle(color: AppColors.inkMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // No Message button here — the sticky bottom bar's chat icon
            // already owns that action.
          ],
        ),
      ),
    );
  }
}

/// The companion's Instagram-style posts grid (3 columns).
class _PostsSection extends ConsumerWidget {
  const _PostsSection({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(companionPostsProvider(companion.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Posts',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (companion.postCount > 0)
              Text('${companion.postCount}',
                  style: const TextStyle(
                      color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
          error: (_, __) => TextButton.icon(
            onPressed: () => ref.invalidate(companionPostsProvider(companion.id)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry loading posts'),
          ),
          data: (posts) {
            if (posts.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.field,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: const Text(
                  'No posts yet.',
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              );
            }
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [for (final p in posts) _PostTile(post: p)],
            );
          },
        ),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final url = post.images.isNotEmpty ? post.images.first : null;
    return GestureDetector(
      onTap: () => context.push(Routes.postPath(post.id)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(color: AppColors.field),
                errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.field),
              )
            else
              const ColoredBox(color: AppColors.field),
            if (post.images.length > 1)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.collections_rounded, size: 15, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reviews: a rating summary header plus the latest reviews (or an honest empty
/// state that never contradicts the rating count).
class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(companionReviewsPreviewProvider(companion.id));
    final hasRatings = companion.ratingCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Reviews',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (hasRatings)
              TextButton(
                onPressed: () =>
                    context.push(Routes.reviewsPath(companion.id)),
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasRatings) ...[
          _RatingSummary(companion: companion),
          const SizedBox(height: AppSpacing.md),
        ],
        async.when(
          loading: () => Column(
            children: [
              for (var i = 0; i < 2; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: ShimmerBox(height: 96, radius: AppSpacing.radius),
                ),
            ],
          ),
          error: (_, __) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                const Icon(Icons.rate_review_outlined,
                    size: 28, color: AppColors.inkMuted),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Couldn't load reviews right now.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => ref.invalidate(
                    companionReviewsPreviewProvider(companion.id),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (reviews) => _list(context, reviews, hasRatings),
        ),
      ],
    );
  }

  Widget _list(
      BuildContext context, List<ReviewModel> reviews, bool hasRatings) {
    if (reviews.isNotEmpty) {
      return Column(
        children: [
          for (final r in reviews)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ReviewCard(review: r),
            ),
          AppButton.outline(
            label: 'Read all reviews',
            icon: Icons.reviews_outlined,
            onPressed: () => context.push(Routes.reviewsPath(companion.id)),
          ),
        ],
      );
    }

    // No written reviews yet. Copy must not contradict the rating count.
    final count = companion.ratingCount;
    final message = hasRatings
        ? 'Rated by $count ${count == 1 ? 'person' : 'people'}. Written reviews will appear here soon.'
        : 'No reviews yet. Be the first to book and review.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(
        children: [
          Icon(
            hasRatings ? Icons.emoji_emotions_outlined : Icons.rate_review_outlined,
            size: 22,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact "4.8 ★★★★★ · based on N ratings" summary card.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = companion.ratingCount;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                companion.rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              StarRow(rating: companion.rating, size: 15),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          Container(width: 1, height: 50, color: AppColors.line),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Loved by guests',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Based on $count ${count == 1 ? 'rating' : 'ratings'}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky bottom bar: price + Message + Book Now.
// ---------------------------------------------------------------------------

class _BookBar extends ConsumerWidget {
  const _BookBar({required this.companion});

  final CompanionModel companion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canBook = companion.status == null || companion.status == 'APPROVED';
    final isOwn = ref.watch(currentUserProvider)?.id == companion.userId;
    final canMessage = companion.userId != null && !isOwn;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Formatters.money(companion.hourlyRate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  Text('per hour',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.inkMuted)),
                ],
              ),
            ),
            if (canMessage) ...[
              const SizedBox(width: AppSpacing.sm),
              _MessageButton(companion: companion),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: GradientButton(
                label: canBook ? 'Book Now' : 'Unavailable',
                icon: Icons.calendar_month_rounded,
                onPressed: canBook
                    ? () => context.push(Routes.bookingPath(companion.id))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular "message" action — get-or-creates the conversation then opens it.
class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({required this.companion});

  final CompanionModel companion;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  bool _busy = false;

  Future<void> _open() async {
    final peerId = widget.companion.userId;
    if (peerId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final convo =
          await ref.read(chatRepositoryProvider).openConversation(peerUserId: peerId);
      if (!mounted) return;
      if (convo.id.isNotEmpty) {
        context.push(Routes.chatThreadPath(convo.id), extra: convo);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not open chat.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _busy ? null : _open,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              )
            : const Icon(Icons.forum_rounded,
                color: AppColors.primary, size: 22),
      ),
    );
  }
}

/// A frosted, dark-scrim circular icon button for use over the photo gallery so
/// the back arrow stays legible on both light and dark photos. Pops the route.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (context.canPop()) {
              context.pop();
            }
          },
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final heroH = (screenH * 0.6).clamp(440.0, 580.0);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ShimmerBox(height: heroH, radius: 0),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          sliver: SliverList.list(
            children: const [
              ShimmerBox(width: double.infinity, height: 48, radius: AppSpacing.radius),
              SizedBox(height: 16),
              ShimmerBox(height: 72, radius: AppSpacing.radius),
              SizedBox(height: 24),
              ShimmerBox(width: double.infinity, height: 80),
              SizedBox(height: 16),
              ShimmerBox(width: double.infinity, height: 80),
            ],
          ),
        ),
      ],
    );
  }
}
