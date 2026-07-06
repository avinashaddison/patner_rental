import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// An Instagram-style post card: author header (+ follow), image carousel,
/// like/comment actions, caption and a Book CTA. Manages optimistic like + follow
/// state locally so taps feel instant.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onDeleted,
    this.showFollow = true,
  });

  final PostModel post;
  final VoidCallback? onDeleted;
  final bool showFollow;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  final _pageController = PageController();
  int _imageIndex = 0;

  late bool _liked = widget.post.isLikedByMe;
  late int _likeCount = widget.post.likeCount;
  late bool _following = widget.post.author?.isFollowing ?? false;
  bool _likeBusy = false;
  bool _followBusy = false;

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) return;
    // Only adopt a server value when it ACTUALLY changed between payloads — never
    // clobber a locally-confirmed optimistic value with a stale (unchanged) one.
    if (!_likeBusy &&
        (oldWidget.post.isLikedByMe != widget.post.isLikedByMe ||
            oldWidget.post.likeCount != widget.post.likeCount)) {
      _liked = widget.post.isLikedByMe;
      _likeCount = widget.post.likeCount;
    }
    final oldFollowing = oldWidget.post.author?.isFollowing ?? false;
    final newFollowing = widget.post.author?.isFollowing ?? false;
    if (!_followBusy && oldFollowing != newFollowing) {
      _following = newFollowing;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  PostModel get post => widget.post;

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final repo = ref.read(feedRepositoryProvider);
    final wasLiked = _liked;
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

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final repo = ref.read(feedRepositoryProvider);
    final wasFollowing = _following;
    setState(() {
      _following = !wasFollowing;
      _followBusy = true;
    });
    try {
      final r = wasFollowing
          ? await repo.unfollow(post.companionId)
          : await repo.follow(post.companionId);
      if (mounted) setState(() => _following = r.following);
      // Refresh Following/Explore so (un)followed companions appear/disappear.
      ref.invalidate(feedProvider);
      ref.invalidate(exploreProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _following = wasFollowing);
        final msg = e is ApiException ? e.message : 'Could not update follow.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This permanently removes the post and its likes and comments.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(feedRepositoryProvider).deletePost(post.id);
      widget.onDeleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not delete the post.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _openDetail() => context.push(Routes.postPath(post.id));
  void _openCompanion() => context.push(Routes.companionPath(post.companionId));

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(author),
          _carousel(),
          _actions(),
          _caption(author),
        ],
      ),
    );
  }

  // ---- Header ----
  Widget _header(PostAuthor? author) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openCompanion,
            child: UserAvatar(photoUrl: author?.photoUrl, name: author?.name, radius: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: _openCompanion,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          author?.name ?? 'Companion',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (author?.isVerified ?? false) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            size: 15, color: AppColors.verified),
                      ],
                    ],
                  ),
                  if (post.createdAt != null)
                    Text(
                      Formatters.relative(post.createdAt!),
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
                    ),
                ],
              ),
            ),
          ),
          if (post.isMine)
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, color: AppColors.inkMuted),
              onPressed: _confirmDelete,
              tooltip: 'Options',
            )
          else if (widget.showFollow)
            _FollowPill(following: _following, busy: _followBusy, onTap: _toggleFollow),
        ],
      ),
    );
  }

  // ---- Image carousel ----
  Widget _carousel() {
    final images = post.images;
    return GestureDetector(
      onTap: _openDetail,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: images.isEmpty
                  ? Container(color: AppColors.field)
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => _imageIndex = i),
                      itemBuilder: (_, i) => CachedNetworkImage(
                        imageUrl: images[i],
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.field),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.field,
                          child: const Icon(Icons.broken_image_rounded,
                              color: AppColors.inkMuted),
                        ),
                      ),
                    ),
            ),
            if (images.length > 1)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    '${_imageIndex + 1}/${images.length}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: i == _imageIndex ? 7 : 5,
                      height: i == _imageIndex ? 7 : 5,
                      decoration: BoxDecoration(
                        color: i == _imageIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
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

  // ---- Action row ----
  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.md, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggleLike,
            icon: Icon(
              _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _liked ? AppColors.primary : AppColors.ink,
            ),
            tooltip: 'Like',
          ),
          if (_likeCount > 0)
            Text('$_likeCount',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _openDetail,
            icon: const Icon(Icons.mode_comment_outlined, color: AppColors.ink),
            tooltip: 'Comments',
          ),
          if (post.commentCount > 0)
            Text('${post.commentCount}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.push(Routes.bookingPath(post.companionId)),
            icon: const Icon(Icons.calendar_month_rounded, size: 17),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            label: const Text('Book', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ---- Caption ----
  Widget _caption(PostAuthor? author) {
    final caption = post.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCaption)
            RichText(
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.35),
                children: [
                  TextSpan(
                    text: '${author?.name ?? 'Companion'}  ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: caption),
                ],
              ),
            ),
          if (post.commentCount > 0) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _openDetail,
              child: Text(
                post.commentCount == 1
                    ? 'View 1 comment'
                    : 'View all ${post.commentCount} comments',
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact Follow / Following pill used in the post header.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.following, required this.busy, required this.onTap});

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: following ? Colors.transparent : AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: following ? AppColors.line : AppColors.primary,
          ),
        ),
        child: Text(
          following ? 'Following' : 'Follow',
          style: TextStyle(
            color: following ? AppColors.inkMuted : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
