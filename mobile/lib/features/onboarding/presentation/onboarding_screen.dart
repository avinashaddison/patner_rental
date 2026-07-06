import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/config/app_config.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/shared/widgets/gradient_button.dart';

const Color _ink = Color(0xFF2C2740);

class _Feature {
  const _Feature({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
}

class _Slide {
  const _Slide({
    required this.titleLead,
    required this.titleRest,
    required this.body,
    required this.features,
  });

  /// Pink, underlined opening of the title (e.g. "Real-life").
  final String titleLead;

  /// Dark remainder of the title (e.g. " social moments").
  final String titleRest;
  final String body;
  final List<_Feature> features;
}

/// Premium 3-slide intro carousel. Each step pairs an admin-editable photo
/// (with floating category chips) with a value-prop headline and feature cards.
/// Routes to `/login` on completion.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_Slide>[
    _Slide(
      titleLead: 'Real-life',
      titleRest: ' social moments',
      body:
          'Book verified companions for everyday activities across Ranchi — '
          'coffee, movies, shopping, events, city tours and good conversation.',
      features: [
        _Feature(
          icon: Icons.star_rounded,
          title: 'Seven curated activity categories',
          subtitle: 'Find the perfect plan for every mood',
        ),
        _Feature(
          icon: Icons.groups_rounded,
          title: 'Browse profiles, ratings and reviews',
          subtitle: 'Choose trusted, verified companions',
        ),
        _Feature(
          icon: Icons.shield_rounded,
          title: 'Transparent hourly pricing',
          subtitle: 'Pay securely and hassle-free in app',
        ),
      ],
    ),
    _Slide(
      titleLead: 'A plus-one',
      titleRest: ' for everything',
      body:
          'From cafés and cinemas to events and weekend day-trips, find friendly '
          'company for whatever you have planned.',
      features: [
        _Feature(
          icon: Icons.event_available_rounded,
          title: 'Book around your schedule',
          subtitle: 'By the hour, whenever it suits you',
        ),
        _Feature(
          icon: Icons.map_rounded,
          title: 'Explore Ranchi together',
          subtitle: 'City tours, food spots and local gems',
        ),
        _Feature(
          icon: Icons.chat_bubble_rounded,
          title: 'Break the ice in-app',
          subtitle: 'Chat first, meet when you are ready',
        ),
      ],
    ),
    _Slide(
      titleLead: 'Safe',
      titleRest: ' & simple to book',
      body:
          'Pick a companion, choose a time and a public place, and you are set — '
          'with secure payments and support all the way.',
      features: [
        _Feature(
          icon: Icons.verified_rounded,
          title: 'Verified companions only',
          subtitle: 'Every profile is KYC-checked',
        ),
        _Feature(
          icon: Icons.place_rounded,
          title: 'Public places, always',
          subtitle: 'Meet at cafés, malls and parks',
        ),
        _Feature(
          icon: Icons.lock_rounded,
          title: 'Secure in-app payments',
          subtitle: 'Your money is protected end-to-end',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => context.go(Routes.login);

  void _next() {
    if (_index < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final heroUrls = ref.watch(appConfigProvider).asData?.value.onboardingImageUrls;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            // Soft pink page background (the curved hero melts into this).
            const Positioned.fill(child: _OnbBackground()),
            Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _SlideView(
                      slide: _slides[i],
                      imageUrl: (heroUrls != null && i < heroUrls.length)
                          ? heroUrls[i]
                          : null,
                      topInset: media.padding.top,
                    ),
                  ),
                ),
                // Page indicator.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.lg + media.padding.bottom,
                  ),
                  child: Column(
                    children: [
                      GradientButton(
                        label: isLast ? 'Get started' : 'Next',
                        trailingIcon: isLast
                            ? Icons.check_rounded
                            : Icons.chevron_right_rounded,
                        onPressed: _next,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 14, color: AppColors.inkMuted),
                          const SizedBox(width: 6),
                          Text(
                            'You must be ${AppConstants.minAge}+ to use '
                            '${AppConstants.appName}.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Fixed brand + Skip overlay, sitting on top of the full-bleed hero.
            Positioned(
              top: media.padding.top + 4,
              left: AppSpacing.xl,
              right: AppSpacing.sm,
              child: _BrandBar(showSkip: !isLast, onSkip: _finish),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.imageUrl,
    required this.topInset,
  });
  final _Slide slide;
  final String? imageUrl;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full-bleed curved hero photo (login-screen style).
          _SlideHero(imageUrl: imageUrl, topInset: topInset),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title: pink underlined lead + dark rest + a heart flourish.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    textAlign: TextAlign.center,
                    TextSpan(
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                      children: [
                        TextSpan(
                          text: slide.titleLead,
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0x66FF4D6D),
                            decorationThickness: 3,
                          ),
                        ),
                        TextSpan(
                          text: slide.titleRest,
                          style: const TextStyle(color: _ink),
                        ),
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.favorite_rounded,
                                color: AppColors.primary, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  slide.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                ...slide.features.map((f) => _FeatureCard(feature: f)),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed romantic hero photo with a curved "valley" bottom edge — the same
/// visual language as the login screen. Admin-set image (cached) with the
/// bundled couple photo as a fallback, top + bottom scrims, floating category
/// chips and a hand-drawn heart doodle.
class _SlideHero extends StatelessWidget {
  const _SlideHero({required this.imageUrl, required this.topInset});
  final String? imageUrl;

  /// Status-bar height — the photo runs edge-to-edge under it, so chips and the
  /// doodle are offset below the brand bar that overlays this region.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    // Big, immersive hero (like the login photo). Includes the status-bar area
    // since the image is full-bleed under it.
    final height = math.max(300.0, MediaQuery.sizeOf(context).height * 0.36);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipPath(
        clipper: _HeroValleyClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _heroImage(imageUrl),
            // Top scrim so the white brand + Skip stay legible over any photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x5C000000), Color(0x00000000)],
                  stops: [0.0, 0.32],
                ),
              ),
            ),
            // Bottom pink melt so the photo blends into the page at the curve.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0x40FFD9E4),
                  ],
                  stops: [0.0, 0.66, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft pink page background; the curved hero melts into this at the bottom.
class _OnbBackground extends StatelessWidget {
  const _OnbBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF1F5), Color(0xFFFFE6EE), Color(0xFFFFDCE7)],
        ),
      ),
    );
  }
}

const List<Shadow> _brandShadow = [
  Shadow(color: Color(0x73000000), blurRadius: 8, offset: Offset(0, 1)),
];

/// Brand mark + "Skip", overlaid in white on top of the full-bleed hero photo.
class _BrandBar extends StatelessWidget {
  const _BrandBar({required this.showSkip, required this.onSkip});
  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: Colors.white, size: 19),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                shadows: _brandShadow,
              ),
            ),
          ],
        ),
        if (showSkip)
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                shadows: _brandShadow,
              ),
            ),
          )
        else
          const SizedBox(height: 48),
      ],
    );
  }
}

/// Curved bottom edge: a gentle valley dipping to the centre — mirrors the
/// login hero so the two screens share one visual language.
class _HeroValleyClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const depth = 42.0;
    final w = size.width;
    final hSide = size.height - depth;
    final hControl = size.height + depth;
    final path = Path()
      ..lineTo(0, hSide)
      ..quadraticBezierTo(w / 2, hControl, w, hSide)
      ..lineTo(w, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Bundled couple photo, falling back to a flat brand colour if it's missing.
Widget _bundledOnbHero() => Image.asset(
      'assets/images/login_couple.png',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (context, error, stack) =>
          const ColoredBox(color: Color(0xFFFFD9E4)),
    );

Widget _heroImage(String? url) {
  if (url == null || url.isEmpty) return _bundledOnbHero();
  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    alignment: Alignment.center,
    placeholder: (_, __) => _bundledOnbHero(),
    errorWidget: (_, __, ___) => _bundledOnbHero(),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(feature.icon, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  feature.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  feature.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.10),
            ),
            child: const Icon(Icons.check_rounded, size: 17, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
