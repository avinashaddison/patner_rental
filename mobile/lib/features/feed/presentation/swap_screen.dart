import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';

/// Soft romantic backdrop so the floating cards pop.
const _kSwapBg = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF2A0F1E), Color(0xFF160A11), Color(0xFF0E0709)],
);

/// Per-session follow overrides keyed by companionId. Lets multiple cards for
/// the SAME companion in the Swap feed stay in sync after a one-tap follow,
/// WITHOUT rebuilding the PageView (which would lose the swipe position). Auto-
/// disposes when Swap closes, so the next open reflects fresh server state.
final swapFollowOverridesProvider =
    NotifierProvider.autoDispose<SwapFollowOverrides, Map<String, bool>>(
        SwapFollowOverrides.new);

class SwapFollowOverrides extends AutoDisposeNotifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String companionId, bool following) {
    state = {...state, companionId: following};
  }
}

/// Compact count formatting: 1234 -> "1.2k".
String _fmtCount(int n) {
  if (n >= 1000000) {
    return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}m';
  }
  if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  }
  return '$n';
}

/// "Swap" — a cute, dating-app-style discovery deck. Each page is a companion's
/// post shown on a floating rounded card with a photo carousel, identity, and a
/// playful Like / Follow / Book action bar. Swipe up/down for the next card,
/// tap the photo edges to browse photos, double-tap to like.
class SwapScreen extends ConsumerWidget {
  const SwapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(exploreProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0709),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _kSwapBg),
        child: postsAsync.when(
          // The header carries the only exit (close) button, so it must be
          // present in EVERY state — otherwise a slow load or an error would
          // trap the user in this nav-less full-screen view.
          loading: () => const Stack(
            children: [
              Center(child: CircularProgressIndicator(color: Colors.white)),
              _SwapHeader(),
            ],
          ),
          error: (e, _) => Stack(
            children: [
              _SwapMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn\'t load Swap',
                message: e is ApiException
                    ? e.message
                    : 'Please check your connection.',
                onRetry: () => ref.invalidate(exploreProvider),
              ),
              const _SwapHeader(),
            ],
          ),
          data: (posts) {
            // Discovery deck: only OTHER companions' published photo posts, so
            // every card has a usable one-tap Follow action.
            final cards = posts
                .where((p) =>
                    p.status == 'PUBLISHED' && p.images.isNotEmpty && !p.isMine)
                .toList(growable: false);
            if (cards.isEmpty) {
              return const Stack(
                children: [
                  _SwapMessage(
                    icon: Icons.favorite_rounded,
                    title: 'Nothing to swap yet',
                    message: 'New companions show up here — check back soon 💕',
                  ),
                  _SwapHeader(),
                ],
              );
            }
            return Stack(
              children: [
                PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: cards.length,
                  // Soft "whoosh" + light haptic each time a new card lands, so
                  // swiping through the deck feels tactile.
                  onPageChanged: (_) => AppSounds.whoosh(),
                  itemBuilder: (_, i) =>
                      _SwapCard(post: cards[i], isFirst: i == 0),
                ),
                const _SwapHeader(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Translucent top header overlaid on the deck: a close button to leave the
/// immersive (nav-less) feed, the brand title, and a refresh button.
class _SwapHeader extends ConsumerWidget {
  const _SwapHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xAA000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: Row(
              children: [
                // Exit the immersive feed (no bottom nav while swiping).
                _GlassIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(Routes.home);
                    }
                  },
                ),
                const Spacer(),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    gradient: AppGradients.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 17),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Swap',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: () => ref.invalidate(exploreProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single floating swipe card with photo carousel + optimistic Like/Follow.
class _SwapCard extends ConsumerStatefulWidget {
  const _SwapCard({required this.post, this.isFirst = false});

  final PostModel post;
  final bool isFirst;

  @override
  ConsumerState<_SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends ConsumerState<_SwapCard> {
  late bool _liked = widget.post.isLikedByMe;
  late int _likeCount = widget.post.likeCount;
  int _photo = 0;
  bool _likeBusy = false;
  bool _followBusy = false;
  bool _burst = false;

  PostModel get post => widget.post;

  bool _isFollowing() =>
      ref.read(swapFollowOverridesProvider)[post.companionId] ??
      (post.author?.isFollowing ?? false);

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final repo = ref.read(feedRepositoryProvider);
    final wasLiked = _liked;
    // Liking is the reward moment — bubbly pop (with haptic). Unliking stays
    // silent apart from a light touch.
    if (!wasLiked) {
      AppSounds.pop();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _liked = !wasLiked;
      _likeCount += wasLiked ? -1 : 1;
      _likeBusy = true;
    });
    try {
      final r = wasLiked ? await repo.unlike(post.id) : await repo.like(post.id);
      if (mounted) {
        setState(() {
          _liked = r.liked;
          _likeCount = r.likeCount;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likeCount += wasLiked ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  /// Double-tap likes (Instagram-style) — never unlikes — and shows a heart pop.
  void _onDoubleTap() {
    if (!_liked) _toggleLike();
    setState(() => _burst = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _burst = false);
    });
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    HapticFeedback.lightImpact();
    final repo = ref.read(feedRepositoryProvider);
    final overrides = ref.read(swapFollowOverridesProvider.notifier);
    final wasFollowing = _isFollowing();
    overrides.set(post.companionId, !wasFollowing);
    setState(() => _followBusy = true);
    try {
      final r = wasFollowing
          ? await repo.unfollow(post.companionId)
          : await repo.follow(post.companionId);
      overrides.set(post.companionId, r.following);
      // NOTE: deliberately do NOT invalidate exploreProvider — that would
      // rebuild the whole PageView and yank the user out of their swipe spot.
    } catch (e) {
      overrides.set(post.companionId, wasFollowing); // revert on failure
      if (mounted) {
        final msg = e is ApiException ? e.message : 'Could not update follow.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _prevPhoto() {
    if (_photo > 0) setState(() => _photo--);
  }

  void _nextPhoto() {
    if (_photo < post.images.length - 1) setState(() => _photo++);
  }

  void _openCompanion() => context.push(Routes.companionPath(post.companionId));
  void _book() => context.push(Routes.bookingPath(post.companionId));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final author = post.author;
    final canFollow = author != null && !post.isMine;
    final following = ref.watch(swapFollowOverridesProvider)[post.companionId] ??
        (author?.isFollowing ?? false);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        media.padding.top + 58,
        12,
        media.padding.bottom + 6,
      ),
      child: Stack(
        children: [
          // Floating photo card.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 142,
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: _card(context, author, following),
            ),
          ),

          // Playful action bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: _actionBar(following: following, canFollow: canFollow),
          ),

          // First-card "swipe up" nudge — sits in the gap above the action bar.
          if (widget.isFirst)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: Center(child: _SwipeHint()),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, PostAuthor? author, bool following) {
    final images = post.images;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 34,
            spreadRadius: -6,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed image (cross-fades between carousel photos).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: SizedBox.expand(
                key: ValueKey('${post.id}-$_photo'),
                child: CachedNetworkImage(
                  imageUrl: images[_photo.clamp(0, images.length - 1)],
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1A1016)),
                  errorWidget: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF1A1016),
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white24, size: 48),
                  ),
                ),
              ),
            ),

            // Readability scrim.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.photoScrim),
              ),
            ),

            // Tap left/right to browse photos.
            if (images.length > 1)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _prevPhoto,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _nextPhoto,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

            // Segmented photo progress (Hinge-style).
            if (images.length > 1)
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: _PhotoProgress(count: images.length, index: _photo),
              ),

            // Identity + chips + caption.
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg + 2,
              child: _info(author),
            ),

            // Double-tap heart pop.
            IgnorePointer(
              child: Center(
                child: AnimatedScale(
                  scale: _burst ? 1 : 0.3,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: _burst ? 1 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 130,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 18)],
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

  Widget _info(PostAuthor? author) {
    final followers = author?.followerCount ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openCompanion,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              _RingAvatar(photoUrl: author?.photoUrl, name: author?.name),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        author?.name ?? 'Companion',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                        ),
                      ),
                    ),
                    if (author?.isVerified ?? false) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.verified_rounded,
                          size: 19, color: AppColors.verified),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            if (author?.isVerified ?? false)
              const _CuteChip(icon: Icons.verified_rounded, label: 'Verified'),
            if (followers > 0)
              _CuteChip(
                icon: Icons.favorite_rounded,
                label: '${_fmtCount(followers)} followers',
              ),
            const _CuteChip(icon: Icons.place_rounded, label: 'Public meetups'),
          ],
        ),
        if (post.caption?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 10),
          Text(
            post.caption!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.3,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionBar({required bool following, required bool canFollow}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Follow (left)
          if (canFollow)
            _CircleAction(
              size: 56,
              icon: following
                  ? Icons.person_rounded
                  : Icons.person_add_alt_1_rounded,
              iconColor: following ? AppColors.primary : Colors.white,
              fill: following ? Colors.white : null,
              label: following ? 'Following' : 'Follow',
              onTap: _followBusy ? null : _toggleFollow,
            ),
          // Book — the big highlighted hero in the centre.
          _CircleAction(
            size: 74,
            icon: Icons.calendar_month_rounded,
            iconColor: Colors.white,
            gradient: AppGradients.primary,
            label: 'Book',
            onTap: _book,
          ),
          // Like (right)
          _CircleAction(
            size: 56,
            icon: _liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: _liked ? AppColors.primary : Colors.white,
            fill: _liked ? Colors.white : null,
            label: _likeCount > 0 ? _fmtCount(_likeCount) : 'Like',
            onTap: _toggleLike,
          ),
        ],
      ),
    );
  }
}

/// Segmented progress bar showing the current photo within a multi-photo card.
class _PhotoProgress extends StatelessWidget {
  const _PhotoProgress({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
            child: Container(
              height: 3.5,
              decoration: BoxDecoration(
                color: i <= index
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A circular action button + label used in the bottom action bar.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.size,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.fill,
    this.gradient,
  });

  final double size;
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;
  final Color? fill;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final hasSolid = gradient != null || fill != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: gradient == null
                  ? (fill ?? Colors.white.withValues(alpha: 0.16))
                  : null,
              gradient: gradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: hasSolid ? 0.0 : 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (gradient != null
                          ? AppColors.primary
                          : Colors.black)
                      .withValues(alpha: gradient != null ? 0.45 : 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size * 0.46),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}

/// A small frosted chip (icon + label) for identity facts.
class _CuteChip extends StatelessWidget {
  const _CuteChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A gently-bouncing "swipe up for more" nudge, shown on the first card and
/// auto-fading after a few seconds.
class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -6 * _ctrl.value),
            child: child,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 4),
                Text(
                  'Swipe up for more',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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

/// Avatar with a soft white ring, for legibility on photos.
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({this.photoUrl, this.name});

  final String? photoUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final initial = (name == null || name!.trim().isEmpty)
        ? '?'
        : name!.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.primaryLight,
        backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
            ? CachedNetworkImageProvider(photoUrl!)
            : null,
        child: (photoUrl == null || photoUrl!.isEmpty)
            ? Text(
                initial,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800),
              )
            : null,
      ),
    );
  }
}

/// A round translucent icon button used in the header.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Centered empty/error message styled for the dark immersive feed.
class _SwapMessage extends StatelessWidget {
  const _SwapMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
