import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/config/app_config.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/settings/presentation/legal_links_text.dart';

/// Cute, dating-app style sign-in. One tap: **Continue with Google**.
///
/// Visual language: a full-bleed romantic hero photo with a curved bottom and
/// an overlapping "companion" logo badge, a "Meet Amazing People" headline, a
/// three-up trust strip (Verified / Secure / Privacy), the white Google CTA and
/// a safety reassurance card.
///
/// Google → Firebase credential → our session via [AuthController.signInWithGoogle].
/// Brand-new users go to `/register` (name + email prefilled from Google); a
/// returning user lands straight on `/home`.
///
/// A hidden long-press on the logo signs in as the demo account for testing
/// before Google is configured for a build.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final result =
          await ref.read(authControllerProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      if (result == null) {
        // User dismissed the Google account chooser — not an error.
        setState(() => _submitting = false);
        return;
      }
      if (result.isNewUser) {
        context.go(Routes.register);
      } else {
        context.go(Routes.home);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _submitting = false;
      });
    }
  }

  Future<void> _devLogin() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref.read(authControllerProvider.notifier).devSignIn();
      if (!mounted) return;
      context.go(Routes.home);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Demo sign-in unavailable. Start the backend or use Google.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final heroHeight = math.max(300.0, media.size.height * 0.42);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: _Background()),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ---- Hero photo with curved bottom + companion logo ----
                  _Hero(
                    height: heroHeight,
                    onLogoLongPress: _submitting ? null : _devLogin,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ---- Headline ----
                  const _Headline(),
                  const SizedBox(height: AppSpacing.xl),

                  // ---- Google CTA (primary action, above the trust strip) ----
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: _GoogleButton(
                      loading: _submitting,
                      onPressed: _submitting ? null : _continueWithGoogle,
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                      child: _ErrorBanner(message: _error!),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),

                  // ---- Trust strip ----
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: _FeatureStrip(),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ---- Legal consent ----
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: LegalConsentText(),
                  ),
                  SizedBox(height: AppSpacing.lg + media.padding.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Hero
// ===========================================================================

/// Full-bleed romantic hero: a couple photo (asset, with a gradient fallback),
/// soft corner foliage, floating hearts, a curved bottom edge and an
/// overlapping circular "companion" logo badge.
class _Hero extends StatelessWidget {
  const _Hero({required this.height, required this.onLogoLongPress});

  final double height;
  final VoidCallback? onLogoLongPress;

  static const double _logoSize = 92;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height + _logoSize / 2,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Curved photo region.
          ClipPath(
            clipper: _HeroClipper(),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: const _HeroBackdrop(),
            ),
          ),

          // Overlapping logo badge sitting in the valley of the curve.
          Positioned(
            top: height - _logoSize / 2,
            child: GestureDetector(
              onLongPress: onLogoLongPress,
              child: const _LogoBadge(size: _logoSize),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero photo plus painted corner foliage and floating hearts.
///
/// Prefers the admin-set remote photo from [appConfigProvider]; while that loads
/// or if it's unset/fails it shows the bundled `login_couple.png`, which itself
/// falls back to a sunset gradient if somehow missing.
class _HeroBackdrop extends ConsumerWidget {
  const _HeroBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteUrl = ref.watch(appConfigProvider).asData?.value.loginHeroImageUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Admin-set photo (cached) with the bundled asset as placeholder/fallback.
        _heroImage(remoteUrl),
        // Soft pink scrim so the photo melts into the page at the curve.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Color(0x33FFD9E4),
              ],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
        ),
        // Corner foliage.
        const Positioned(
          top: 0,
          left: 0,
          child: CustomPaint(
            size: Size(150, 130),
            painter: _FoliagePainter(mirror: false),
          ),
        ),
        const Positioned(
          top: 0,
          right: 0,
          child: CustomPaint(
            size: Size(150, 130),
            painter: _FoliagePainter(mirror: true),
          ),
        ),
        // Floating hearts.
        const Positioned(top: 70, left: 0, right: 0, child: _PuffHeart(size: 30)),
        const Positioned(top: 150, left: 34, child: _PuffHeart(size: 24)),
        const Positioned(top: 130, right: 30, child: _PuffHeart(size: 34)),
      ],
    );
  }
}

/// The bundled couple photo, falling back to a sunset gradient if it's missing.
Widget _bundledHero() => Image.asset(
      'assets/images/login_couple.png',
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stack) => const _SunsetFallback(),
    );

/// The hero image: the admin-set [url] (cached) when present, otherwise the
/// bundled photo. The remote image uses the bundled photo as both its loading
/// placeholder and its error fallback, so the hero never flashes blank.
Widget _heroImage(String? url) {
  if (url == null || url.isEmpty) return _bundledHero();
  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    placeholder: (_, __) => _bundledHero(),
    errorWidget: (_, __, ___) => _bundledHero(),
  );
}

/// Romantic sunset gradient used when no hero photo asset is present.
class _SunsetFallback extends StatelessWidget {
  const _SunsetFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFD0C4), // warm peach sky
            Color(0xFFFFB0C8),
            Color(0xFFFF89AC),
            Color(0xFFFF6F91), // rose horizon
          ],
        ),
      ),
      child: DecoratedBox(
        // Soft sun glow.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 0.7,
            colors: [Color(0x66FFFFFF), Colors.transparent],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}

/// Curved bottom edge: a gentle valley that dips to the centre, where the logo
/// badge nests.
class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const depth = 42.0;
    final w = size.width;
    final hSide = size.height - depth;
    final hControl = size.height + depth; // pulls the midpoint to size.height
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

/// Stylised translucent leaves fanning from a top corner.
class _FoliagePainter extends CustomPainter {
  const _FoliagePainter({required this.mirror});
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()..style = PaintingStyle.fill;
    final colors = [
      const Color(0x55C83E63),
      const Color(0x44E2547A),
      const Color(0x66B5345A),
    ];
    // A handful of leaves at varying angles from the corner.
    final specs = <List<double>>[
      // [originX, originY, angleDeg, length, width]
      [4, -6, 35, 96, 30],
      [10, 6, 60, 80, 24],
      [-6, 20, 18, 70, 22],
      [30, -4, 48, 64, 20],
      [2, 40, 75, 56, 18],
    ];
    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      paint.color = colors[i % colors.length];
      _leaf(canvas, paint, Offset(s[0], s[1]), s[2], s[3], s[4]);
    }
  }

  void _leaf(Canvas canvas, Paint paint, Offset origin, double angleDeg,
      double length, double width) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angleDeg * math.pi / 180);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(width, length * 0.35, 0, length)
      ..quadraticBezierTo(-width, length * 0.35, 0, 0)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoliagePainter oldDelegate) =>
      oldDelegate.mirror != mirror;
}

/// A cute, slightly-3D filled heart sticker with a soft drop shadow.
class _PuffHeart extends StatelessWidget {
  const _PuffHeart({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.favorite_rounded,
      size: size,
      color: const Color(0xFFFF6E96),
      shadows: const [
        Shadow(color: Color(0x33FF2D6A), blurRadius: 10, offset: Offset(0, 4)),
      ],
    );
  }
}

/// White-ringed circular badge with a pink gradient and the "two people +
/// heart" companion glyph.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF7EB3), Color(0xFFFF4D6D)],
          ),
        ),
        child: Center(
          child: CustomPaint(
            size: Size(size * 0.5, size * 0.5),
            painter: _CompanionGlyphPainter(),
          ),
        ),
      ),
    );
  }
}

/// Two heads above a heart — the companionship mark, painted white.
class _CompanionGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Heart body.
    final heart = Path();
    final cx = w / 2;
    final top = h * 0.42;
    final bottom = h * 1.02;
    heart.moveTo(cx, bottom);
    heart.cubicTo(-w * 0.10, h * 0.72, w * 0.12, top * 0.7, cx, top);
    heart.cubicTo(w * 0.88, top * 0.7, w * 1.10, h * 0.72, cx, bottom);
    heart.close();
    canvas.drawPath(heart, white);

    // Two heads, spaced apart with a clear gap so the mark reads as two
    // distinct people (centres 0.40w apart vs 2*0.145w diameter -> ~0.11w gap).
    final headR = w * 0.145;
    canvas.drawCircle(Offset(w * 0.30, h * 0.19), headR, white);
    canvas.drawCircle(Offset(w * 0.70, h * 0.19), headR, white);

    // Small heart notch in the centre (negative space) for the "two people"
    // read. Painted with the gradient's mid-tone (sampled where the notch sits)
    // so it blends into the diagonal badge gradient with no visible seam.
    final notch = Paint()..color = const Color(0xFFFF6088);
    final n = Path();
    final ncx = cx;
    final ntop = h * 0.58;
    final nbottom = h * 0.82;
    n.moveTo(ncx, nbottom);
    n.cubicTo(w * 0.34, h * 0.66, w * 0.42, ntop * 0.92, ncx, ntop);
    n.cubicTo(w * 0.58, ntop * 0.92, w * 0.66, h * 0.66, ncx, nbottom);
    n.close();
    canvas.drawPath(n, notch);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// Headline
// ===========================================================================

class _Headline extends StatelessWidget {
  const _Headline();

  static const _dark = Color(0xFF2C2740);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Meet Amazing',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: _dark,
            letterSpacing: -0.5,
            height: 1.05,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'People',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF4D7D),
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 8),
              // Solid heart with a little sparkle — the accent beside "People".
              const SizedBox(
                width: 34,
                height: 32,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      bottom: 1,
                      child: Icon(Icons.favorite_rounded,
                          color: Color(0xFFFF4D7D), size: 26),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Icon(Icons.auto_awesome,
                          color: Color(0xFFFF9DBB), size: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Text(
            'Safe, verified and meaningful experiences around you 💗',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SocialProof(),
      ],
    );
  }
}

/// A small stack of avatars plus a "trusted by" line — social proof shown
/// under the headline.
class _SocialProof extends StatelessWidget {
  const _SocialProof();

  static const List<Color> _avatarColors = [
    Color(0xFFFF7EB3),
    Color(0xFFFF5C8A),
    Color(0xFFFFA5B8),
    Color(0xFFFF4D6D),
  ];

  @override
  Widget build(BuildContext context) {
    const double size = 30;
    const double overlap = 11;
    final count = _avatarColors.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size + (count - 1) * (size - overlap),
          height: size,
          child: Stack(
            children: [
              for (var i = 0; i < count; i++)
                Positioned(
                  left: i * (size - overlap),
                  child: _MiniAvatar(color: _avatarColors[i]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 13,
              color: AppColors.inkMuted,
              height: 1.2,
            ),
            children: [
              TextSpan(text: 'Trusted by '),
              TextSpan(
                text: '1000+',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF4D7D),
                ),
              ),
              TextSpan(text: ' people in Ranchi'),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.person_rounded, color: Colors.white, size: 16),
    );
  }
}

// ===========================================================================
// Trust strip
// ===========================================================================

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        children: [
          Expanded(
            child: _FeatureCell(
              icon: Icons.verified_user_rounded,
              title: 'Verified',
              subtitle: 'Profiles',
            ),
          ),
          _CellDivider(),
          Expanded(
            child: _FeatureCell(
              icon: Icons.lock_rounded,
              title: 'Secure',
              subtitle: 'Payments',
            ),
          ),
          _CellDivider(),
          Expanded(
            child: _FeatureCell(
              icon: Icons.shield_rounded,
              title: 'Privacy',
              subtitle: 'Protected',
            ),
          ),
        ],
      ),
    );
  }
}

class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: AppColors.line,
    );
  }
}

class _FeatureCell extends StatelessWidget {
  const _FeatureCell({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFE9F0),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFFF5C8A)),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C2740),
                  height: 1.1,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkMuted,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Google CTA
// ===========================================================================

/// The official-style white "Continue with Google" button: the four-colour G
/// pinned to the left, the label optically centred.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = loading || onPressed == null;

    return SizedBox(
      width: double.infinity,
      height: 62,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: disabled ? null : onPressed,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: loading
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: AppSpacing.xl,
                        child: Image.asset(
                          'assets/images/google.png',
                          width: 26,
                          height: 26,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D2D33),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Shared
// ===========================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Romantic pink page background with a couple of faint hearts near the foot.
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF1F5),
            Color(0xFFFFE6EE),
            Color(0xFFFFDCE7),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 70,
            left: 28,
            child: Icon(Icons.favorite_rounded,
                size: 20, color: Color(0x14FF4D6D)),
          ),
          Positioned(
            bottom: 40,
            right: 40,
            child: Icon(Icons.favorite_rounded,
                size: 26, color: Color(0x14FF4D6D)),
          ),
        ],
      ),
    );
  }
}
