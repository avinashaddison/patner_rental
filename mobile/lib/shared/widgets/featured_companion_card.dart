import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';

/// Soft shadow shared by home cards.
const _softShadow = BoxShadow(
  color: Color(0x0F000000), // black @ ~6%
  blurRadius: 16,
  offset: Offset(0, 6),
);

// ---- Palette ----
const Color _kPink = Color(0xFFF7568F); // brand accent (heart ring)
const Color _kHeart = Color(0xFFE53935); // liked heart — red
// Hairline gradient border around the card.
const Color _kBorder1 = Color(0xFFFFDCEC);
const Color _kBorder2 = Color(0xFFFFA3C8);
// "Rent Now" CTA gradient (bright, luminous pink).
const Color _kBtn1 = Color(0xFFFF74B4);
const Color _kBtn2 = Color(0xFFFF4890);
// Bare verified tick over the photo — bright green so it reads on any image.
const Color _kVerifiedTick = Color(0xFF3DDC84);

/// Full-photo featured companion card: the tall portrait IS the card, with
/// everything overlaid on it — Popular/Trending/New badge, wishlist heart,
/// location + Verified chips, the full name, and a price + glowing "Rent Now"
/// row at the bottom. No white footer.
class FeaturedCompanionCard extends StatefulWidget {
  const FeaturedCompanionCard({
    super.key,
    required this.companion,
    this.onTap,
    this.onBook,
    this.width = 170,
  });

  final CompanionModel companion;
  final VoidCallback? onTap;
  final VoidCallback? onBook;
  final double width;

  @override
  State<FeaturedCompanionCard> createState() => _FeaturedCompanionCardState();
}

class _FeaturedCompanionCardState extends State<FeaturedCompanionCard> {
  bool _pressed = false;
  bool _liked = false;
  bool _heartBounce = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  Future<void> _toggleLike() async {
    if (!_liked) AppSounds.pop();
    setState(() {
      _liked = !_liked;
      _heartBounce = true;
    });
    await Future.delayed(const Duration(milliseconds: 140));
    if (mounted) setState(() => _heartBounce = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.companion;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        // Outer layer = the gradient hairline border (1.5px reveal).
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [_kBorder1, _kBorder2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kPink.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.5),
            child: AspectRatio(
              aspectRatio: 0.72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Photo(url: c.primaryPhotoUrl),
                  // Bottom scrim so name + price/CTA stay legible.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x33000000),
                            Color(0xCC000000),
                          ],
                          stops: [0.4, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // TOP-LEFT: location pill (where the badge used to sit).
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _LocationPill(
                      text: c.distanceKm != null
                          ? Formatters.distance(c.distanceKm)
                          : c.city,
                    ),
                  ),
                  // TOP-RIGHT: wishlist heart.
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: _toggleLike,
                      child: AnimatedScale(
                        scale: _heartBounce ? 1.3 : 1.0,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            _liked ? Icons.favorite : Icons.favorite_border,
                            size: 17,
                            color: _liked ? _kHeart : _kPink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // BOTTOM: name + verified tick, then price + Rent Now.
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Full name + a bare green verified tick — no age, no
                        // location pill, no text chip: maximum room for the name.
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            if (c.isVerified) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.verified_rounded,
                                size: 17,
                                color: _kVerifiedTick,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 9),
                        // CTA on the LEFT, price on the RIGHT.
                        Row(
                          children: [
                            _RentNowButton(onTap: widget.onBook),
                            const SizedBox(width: 6),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text.rich(
                                  TextSpan(
                                    text:
                                        '₹${c.hourlyRate.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: ' /hr',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.75),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark rounded "location" chip (top-left photo overlay).
class _LocationPill extends StatelessWidget {
  const _LocationPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bright "Rent Now" stadium button with a light glowing border — sits over
/// the photo, so the white ring keeps its edge crisp against any image.
class _RentNowButton extends StatefulWidget {
  const _RentNowButton({this.onTap});
  final VoidCallback? onTap;

  @override
  State<_RentNowButton> createState() => _RentNowButtonState();
}

class _RentNowButtonState extends State<_RentNowButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [_kBtn1, _kBtn2]),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
            boxShadow: [
              // Pink glow…
              BoxShadow(
                color: _kBtn2.withValues(alpha: 0.55),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              // …plus a soft white halo hugging the light border.
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.35),
                blurRadius: 6,
              ),
            ],
          ),
          child: const Text(
            'Rent Now',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "Near You" mini-card (white, rounded-16, ~230 wide).
class NearYouMiniCard extends StatelessWidget {
  const NearYouMiniCard({
    super.key,
    required this.companion,
    this.onTap,
    this.width = 210,
  });

  final CompanionModel companion;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: AppColors.line),
              boxShadow: const [_softShadow],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: _Photo(url: companion.primaryPhotoUrl),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                companion.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (companion.isVerified) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.verified,
                                  size: 13, color: AppColors.verified),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.online,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                companion.distanceKm != null
                                    ? Formatters.distance(companion.distanceKm)
                                    : companion.city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.inkMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '₹${companion.hourlyRate.toStringAsFixed(0)}/hour',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.favorite_border,
                      size: 18, color: AppColors.gold),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cached photo with a soft cream placeholder and person-icon error widget.
class _Photo extends StatelessWidget {
  const _Photo({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const _PhotoPlaceholder();
    }
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
    return const ColoredBox(
      color: AppColors.field,
      child: Center(
        child: Icon(Icons.person_rounded, size: 40, color: AppColors.inkMuted),
      ),
    );
  }
}
