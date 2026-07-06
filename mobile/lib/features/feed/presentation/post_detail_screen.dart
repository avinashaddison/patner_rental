import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/post_comment_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';
import 'package:companion_ranchi/features/feed/presentation/widgets/post_card.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Full post view: the post card + its comments + an inline comment composer.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _postId => widget.postId;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(feedRepositoryProvider).addComment(_postId, text);
      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();
      ref.invalidate(postCommentsProvider(_postId));
      ref.invalidate(postDetailProvider(_postId));
      // Refresh feed cards so their "View all N comments" count stays accurate.
      final cid = ref.read(postDetailProvider(_postId)).valueOrNull?.companionId;
      invalidateFeeds(ref, companionId: cid);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not post your comment.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(PostComment c) async {
    try {
      await ref.read(feedRepositoryProvider).deleteComment(c.id);
      ref.invalidate(postCommentsProvider(_postId));
      ref.invalidate(postDetailProvider(_postId));
      final cid = ref.read(postDetailProvider(_postId)).valueOrNull?.companionId;
      invalidateFeeds(ref, companionId: cid);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Could not delete the comment.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postDetailProvider(_postId));
    final commentsAsync = ref.watch(postCommentsProvider(_postId));
    final myUserId = ref.watch(currentUserProvider)?.id;
    final isPostOwner = postAsync.valueOrNull?.isMine ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: _CommentComposer(
            controller: _controller,
            sending: _sending,
            onSend: _send,
          ),
        ),
      ),
      body: postAsync.when(
        loading: () => const LoadingView(message: 'Loading post…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(postDetailProvider(_postId)),
        ),
        data: (post) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            PostCard(post: post, onDeleted: () => Navigator.of(context).maybePop()),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Comments',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            commentsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              ),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(postCommentsProvider(_postId)),
              ),
              data: (comments) {
                if (comments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: Text(
                        'No comments yet. Say something nice 👋',
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final c in comments)
                      _CommentTile(
                        comment: c,
                        canDelete: isPostOwner || (myUserId != null && c.user?.id == myUserId),
                        onDelete: () => _delete(c),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.canDelete, required this.onDelete});

  final PostComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(photoUrl: comment.user?.photoUrl, name: comment.user?.name, radius: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.35),
                    children: [
                      TextSpan(
                        text: '${comment.user?.name ?? 'User'}  ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: comment.body),
                    ],
                  ),
                ),
                if (comment.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      Formatters.relative(comment.createdAt!),
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          if (canDelete)
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Add a comment…',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
