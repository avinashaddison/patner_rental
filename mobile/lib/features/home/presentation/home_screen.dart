import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/config/app_config.dart';
import 'package:companion_ranchi/core/models/category_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/home/application/home_providers.dart';
import 'package:companion_ranchi/features/home/presentation/location_picker.dart';
import 'package:companion_ranchi/features/notifications/application/notifications_controller.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Soft shadow shared by all home cards.
const _softShadow = BoxShadow(
  color: Color(0x0F000000), // black @ ~6%
  blurRadius: 16,
  offset: Offset(0, 6),
);

const _kHPad = 18.0;

/// Premium GOLD-on-CREAM discovery home: top bar (greeting + wallet), search,
/// hero carousel, categories, featured companions, refer banner, trust badges
/// and a "Near You" rail. All data is fetched from the existing home/wallet
/// providers and rendered with shimmer skeletons + retry/empty states.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(homeCategoriesProvider);
    ref.invalidate(featuredCompanionsProvider);
    ref.invalidate(popularNearbyProvider);
    await Future.wait([
      ref.read(featuredCompanionsProvider.future),
      ref.read(popularNearbyProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstNameRaw =
        (user?.fullName ?? '').trim().split(RegExp(r'\s+')).first;
    final firstName = firstNameRaw.isEmpty ? 'there' : firstNameRaw;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          color: AppColors.gold,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: AppSpacing.sm),
              _TopBar(firstName: firstName),
              const SizedBox(height: AppSpacing.md),
              const _SearchBar(),
              const SizedBox(height: AppSpacing.md),
              const _HeroCarousel(),
              const SizedBox(height: AppSpacing.md),
              const _CategoriesRow(),
              const SizedBox(height: AppSpacing.md),
              const _TrustBadges(),
              const SizedBox(height: AppSpacing.md),
              const _FeaturedSection(),
              const SizedBox(height: AppSpacing.md),
              const _ReferBanner(),
              const SizedBox(height: AppSpacing.md),
              const _NearYouSection(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

String _greeting() => 'Hey,';

// ---------------------------------------------------------------------------
// (A) TOP BAR
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // Real unread-notification count (0 → the badge hides itself).
    final unreadNotifs =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kHPad, 4, _kHPad, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Tappable profile avatar (replaces the old, non-functional menu icon)
          // — quick access to the Profile tab and a friendlier dating-app header.
          GestureDetector(
            onTap: () => context.go(Routes.profile),
            child: UserAvatar(
              photoUrl: user?.profilePhotoUrl,
              name: user?.fullName ?? firstName,
              radius: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Greeting + first name on ONE single line.
                Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${_greeting()} ',
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            TextSpan(
                              text: '$firstName 👋',
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Tappable location — opens the "Set your location" picker.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showLocationPicker(context),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: AppColors.gold, size: 13),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          ref.watch(selectedLocationProvider)?.label ??
                              'Ranchi, Jharkhand',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down,
                          color: AppColors.inkMuted, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Companion dashboard shortcut (non-companions land on the
          // "Become a Companion" onboarding funnel there).
          _IconPillButton(
            icon: Icons.space_dashboard_rounded,
            tooltip: 'Companion dashboard',
            onTap: () => context.push(Routes.companionDashboard),
          ),
          const SizedBox(width: 8),
          _NotificationButton(
            count: unreadNotifs,
            onTap: () => context.push(Routes.notifications),
          ),
        ],
      ),
    );
  }
}

/// A plain 40×40 pill icon button matching [_NotificationButton]'s style
/// (no badge) — used for the companion-dashboard shortcut in the top bar.
class _IconPillButton extends StatelessWidget {
  const _IconPillButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
            boxShadow: const [_softShadow],
          ),
          child: Icon(icon, color: AppColors.ink, size: 21),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
            boxShadow: const [_softShadow],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.notifications_outlined,
                  color: AppColors.ink, size: 21),
              if (count > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 15, minHeight: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (B) SEARCH BAR
// ---------------------------------------------------------------------------
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.go(Routes.search),
                child: Ink(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                    boxShadow: const [_softShadow],
                  ),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            color: AppColors.inkMuted, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Search companion, category or anything…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go(Routes.search),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.tune, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (C) HERO CAROUSEL
// ---------------------------------------------------------------------------
class _HeroCarousel extends ConsumerStatefulWidget {
  const _HeroCarousel();

  @override
  ConsumerState<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<_HeroCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The home carousel shows ONLY admin-uploaded banner images — no default
    // marketing card. When nothing is uploaded, the whole section is hidden.
    final banners =
        ref.watch(appConfigProvider).asData?.value.homeBanners ??
            const <String>[];
    if (banners.isEmpty) return const SizedBox.shrink();

    final activePage = _page < banners.length ? _page : 0;

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _HeroBannerCard(
                  url: banners[i],
                  onTap: () => context.go(Routes.search),
                ),
              );
            },
          ),
        ),
        if (banners.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(banners.length, (i) {
              final active = i == activePage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? AppColors.gold : AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// A full-bleed admin-uploaded promo image used as a home carousel slide.
class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: const [_softShadow],
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
          placeholder: (_, __) => Container(color: AppColors.field),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.field,
            alignment: Alignment.center,
            child: const Icon(Icons.image_outlined,
                color: AppColors.inkMuted, size: 40),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (D) CATEGORIES ROW
// ---------------------------------------------------------------------------
class _CategoryDisplay {
  const _CategoryDisplay(this.icon, this.label);
  final IconData icon;
  final String label;
}

_CategoryDisplay _categoryDisplay(CategoryModel c) {
  switch (c.slug) {
    case 'coffee-partner':
      return const _CategoryDisplay(Icons.local_cafe_rounded, 'Coffee');
    case 'movie-partner':
      return const _CategoryDisplay(Icons.movie_rounded, 'Movies');
    case 'shopping-partner':
      return const _CategoryDisplay(Icons.shopping_bag_rounded, 'Shopping');
    case 'event-companion':
      return const _CategoryDisplay(Icons.celebration_rounded, 'Events');
    case 'city-guide':
      return const _CategoryDisplay(Icons.map_rounded, 'City Tour');
    case 'travel-companion':
      return const _CategoryDisplay(Icons.flight_rounded, 'Travel');
    case 'networking-partner':
      return const _CategoryDisplay(Icons.groups_rounded, 'Network');
    default:
      return _CategoryDisplay(Icons.category_rounded, c.name);
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeCategoriesProvider);
    // Admin-controlled icon size (fraction of the tile the icon fills).
    final iconScale =
        ref.watch(appConfigProvider).valueOrNull?.categoryIconScale ?? 0.46;
    return async.when(
      loading: () => const SizedBox(
        height: 88,
        child: _CategoriesSkeleton(),
      ),
      error: (e, _) => _SectionRetry(
        height: 88,
        message: "Couldn't load categories.",
        onRetry: () => ref.invalidate(homeCategoriesProvider),
      ),
      data: (categories) {
        if (categories.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _kHPad),
            itemCount: categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              if (i == categories.length) {
                return _CategoryItem(
                  icon: Icons.grid_view_rounded,
                  label: 'All',
                  selected: false,
                  iconScale: iconScale,
                  onTap: () => context.go(Routes.search),
                );
              }
              final c = categories[i];
              final d = _categoryDisplay(c);
              return _CategoryItem(
                icon: d.icon,
                label: d.label,
                iconUrl: c.iconUrl,
                selected: i == 0,
                iconScale: iconScale,
                onTap: () => context.push(Routes.categoryPath(c.slug)),
              );
            },
          ),
        );
      },
    );
  }
}

// ---- Category tile geometry ----
const double _kCatCircle = 58; // outer circle diameter
const double _kCatBorder = 1.4; // light ring thickness around the icon

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconUrl,
    this.iconScale = 0.46,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Optional uploaded image (Cloudinary) shown full-bleed in the tile.
  final String? iconUrl;

  /// Admin-controlled fraction of the tile the icon fills (0..1). Higher =
  /// bigger icon. Drives both the inset (for photos) and the vector glyph size.
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    // Inner white disc diameter, then derive the icon size + inset from the
    // admin scale so photos and vector glyphs stay the same visual size. The
    // upper clamp keeps a 1px gap so even at 100% the icon never touches the
    // ring (and the circular clip guarantees it can't spill outside it).
    const inner = _kCatCircle - 2 * _kCatBorder;
    final iconSize = (inner * iconScale).clamp(12.0, inner - 2.0);
    final inset = (inner - iconSize) / 2;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Simple circular icon: a plain light border on every category
            // (no coloured "active" ring). The icon/photo sits inset so it never
            // touches the border. Selection is shown by the label + underline.
            Container(
              width: _kCatCircle,
              height: _kCatCircle,
              padding: const EdgeInsets.all(_kCatBorder),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.line,
              ),
              child: Container(
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                padding: EdgeInsets.all(inset),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                ),
                child: (iconUrl != null && iconUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: iconUrl!,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Icon(icon,
                            color: AppColors.goldDeep, size: iconSize),
                        errorWidget: (_, __, ___) => Icon(icon,
                            color: AppColors.goldDeep, size: iconSize),
                      )
                    : Icon(icon, color: AppColors.goldDeep, size: iconSize),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppColors.goldDeep : AppColors.inkMuted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 3,
              width: 18,
              decoration: BoxDecoration(
                color: selected ? AppColors.gold : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (_, __) => const SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShimmerBox(width: 50, height: 50, radius: 16),
            SizedBox(height: 6),
            ShimmerBox(width: 40, height: 10),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (E) FEATURED COMPANIONS
// ---------------------------------------------------------------------------
class _FeaturedSection extends ConsumerWidget {
  const _FeaturedSection();

  // Wide luxury cards: ~1.8 visible (bigger, roomier). Wider than before so the
  // name, price and CTA get more breathing room.
  // width = (screenWidth - 2*pad - 2*gap) / 1.8  (~185–195dp).
  static const double _featuredPad = 16;
  static const double _featuredGap = 14;

  static double _cardWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w - 2 * _featuredPad - 2 * _featuredGap) / 1.8;
  }

  // The card IS the photo (AspectRatio 0.72 — everything overlays it).
  // Rail = photo + 8px border reveal / rounding slack.
  static double _railHeight(double cardWidth) => cardWidth / 0.72 + 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(featuredCompanionsProvider);
    final cardWidth = _cardWidth(context);
    final railHeight = _railHeight(cardWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header (19px bold + gold "View All").
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _featuredPad),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '✨ Featured Companions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.go(Routes.search),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'View All →',
                    style: TextStyle(
                      color: AppColors.goldDeep,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: railHeight,
          child: async.when(
            loading: () => _featuredLoading(cardWidth),
            error: (e, _) => _SectionRetry(
              height: railHeight,
              message: "Couldn't load featured companions.",
              onRetry: () => ref.invalidate(featuredCompanionsProvider),
            ),
            data: (companions) {
              if (companions.isEmpty) {
                return _SectionEmpty(
                  height: railHeight,
                  message: 'No featured companions yet. Check back soon.',
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: _featuredPad),
                itemCount: companions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: _featuredGap),
                itemBuilder: (context, i) {
                  final c = companions[i];
                  return FeaturedCompanionCard(
                    companion: c,
                    width: cardWidth,
                    onTap: () => context.push(Routes.companionPath(c.id)),
                    onBook: () => context.push(Routes.bookingPath(c.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _featuredLoading(double cardWidth) {
    // Matches the full-photo card: a single shimmer filling the whole rail
    // height (the card IS the photo now — no separate white footer).
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _featuredPad),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: _featuredGap),
      itemBuilder: (_, __) => SizedBox(
        width: cardWidth,
        height: double.infinity,
        child: const ShimmerBox(
          width: double.infinity,
          height: double.infinity,
          radius: 22.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (F) REFER BANNER
// ---------------------------------------------------------------------------
class _ReferBanner extends StatelessWidget {
  const _ReferBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite & Earn 🎁',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Refer friends, get rewards',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkInkMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(Routes.profile),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Refer Now →',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// (G) TRUST BADGES
// ---------------------------------------------------------------------------
/// Trust strip under the categories: three colourful proof points (green
/// verified shield, violet safety shield, pink nearby pin) in one white pill.
class _TrustBadges extends StatelessWidget {
  const _TrustBadges();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          boxShadow: const [_softShadow],
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TrustItem(
                  icon: Icons.verified_user_rounded,
                  color: Color(0xFF22A85B),
                  title: 'Verified',
                  subtitle: 'Profiles',
                ),
              ),
              _TrustDivider(),
              Expanded(
                child: _TrustItem(
                  icon: Icons.shield_rounded,
                  color: Color(0xFF7C3AED),
                  title: 'Trusted',
                  subtitle: '& Safe',
                ),
              ),
              _TrustDivider(),
              Expanded(
                child: _TrustItem(
                  icon: Icons.location_on_rounded,
                  color: AppColors.primary,
                  title: 'Nearby',
                  subtitle: 'Companions',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustDivider extends StatelessWidget {
  const _TrustDivider();

  @override
  Widget build(BuildContext context) {
    return const VerticalDivider(
      width: 1,
      thickness: 1,
      color: AppColors.line,
      indent: 4,
      endIndent: 4,
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 9.5,
                    height: 1.15,
                  ),
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
// (H) NEAR YOU
// ---------------------------------------------------------------------------
class _NearYouSection extends ConsumerWidget {
  const _NearYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(popularNearbyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(
          icon: Icons.location_on,
          title: 'Near You',
          onViewAll: () => context.go(Routes.search),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: async.when(
            loading: _nearYouLoading,
            error: (e, _) => _SectionRetry(
              height: 76,
              message: "Couldn't load companions nearby.",
              onRetry: () => ref.invalidate(popularNearbyProvider),
            ),
            data: (companions) {
              if (companions.isEmpty) {
                return const _SectionEmpty(
                  height: 76,
                  message: 'No companions nearby yet.',
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: _kHPad),
                itemCount: companions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final c = companions[i];
                  return NearYouMiniCard(
                    companion: c,
                    onTap: () => context.push(Routes.companionPath(c.id)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _nearYouLoading() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, __) => Container(
        width: 210,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          boxShadow: const [_softShadow],
        ),
        child: const Row(
          children: [
            ShimmerBox(width: 56, height: 56, radius: 12),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShimmerBox(width: 90, height: 12),
                  SizedBox(height: 6),
                  ShimmerBox(width: 60, height: 10),
                  SizedBox(height: 6),
                  ShimmerBox(width: 50, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared home helpers
// ---------------------------------------------------------------------------
class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.icon,
    required this.title,
    required this.onViewAll,
  });

  final IconData icon;
  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHPad),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onViewAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'View All →',
                style: TextStyle(
                  color: AppColors.goldDeep,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRetry extends StatelessWidget {
  const _SectionRetry({
    required this.height,
    required this.message,
    required this.onRetry,
  });

  final double height;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.height, required this.message});

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// Cached photo helper for home hero (soft placeholder + person-icon error).
class HomePhoto extends StatelessWidget {
  const HomePhoto({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const _HeroPhotoPlaceholder();
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: AppColors.darkSoft),
      errorWidget: (_, __, ___) => const _HeroPhotoPlaceholder(),
    );
  }
}

class _HeroPhotoPlaceholder extends StatelessWidget {
  const _HeroPhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.darkSoft,
      child: Center(
        child: Icon(Icons.person_rounded, size: 40, color: AppColors.gold),
      ),
    );
  }
}
