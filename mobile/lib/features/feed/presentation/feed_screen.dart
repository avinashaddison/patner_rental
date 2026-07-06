import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/presentation/widgets/post_card.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// The social feed — a "Following" tab (posts from companions you follow) and an
/// "Explore" tab (discover everyone). Companions get a compose FAB.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompanion = ref.watch(currentUserProvider)?.isCompanion ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.inkMuted,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          tabs: const [Tab(text: 'Following'), Tab(text: 'Explore')],
        ),
      ),
      floatingActionButton: isCompanion
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.postCompose),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
              label: const Text('New post',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _PostList(
            provider: feedProvider,
            onRefresh: () => ref.refresh(feedProvider.future),
            emptyTitle: 'Your feed is quiet',
            emptyMessage:
                'Follow companions to see their latest photos here. Tap Explore to discover people.',
            emptyIcon: Icons.dynamic_feed_rounded,
            onEmptyAction: () => _tabs.animateTo(1),
            emptyActionLabel: 'Go to Explore',
          ),
          _PostList(
            provider: exploreProvider,
            onRefresh: () => ref.refresh(exploreProvider.future),
            emptyTitle: 'No posts yet',
            emptyMessage: 'Companions haven’t shared any photos yet. Check back soon!',
            emptyIcon: Icons.photo_library_outlined,
          ),
        ],
      ),
    );
  }
}

/// A pull-to-refresh list bound to a posts [FutureProvider].
class _PostList extends ConsumerWidget {
  const _PostList({
    required this.provider,
    required this.onRefresh,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    this.onEmptyAction,
    this.emptyActionLabel,
  });

  final ProviderListenable<AsyncValue<List<PostModel>>> provider;
  final Future<void> Function() onRefresh;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback? onEmptyAction;
  final String? emptyActionLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const LoadingView(message: 'Loading posts…'),
      error: (e, _) => ErrorView(error: e, onRetry: onRefresh),
      data: (posts) {
        if (posts.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                EmptyView(
                  icon: emptyIcon,
                  title: emptyTitle,
                  message: emptyMessage,
                  actionLabel: emptyActionLabel,
                  onAction: onEmptyAction,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
            itemCount: posts.length,
            itemBuilder: (_, i) => PostCard(
              key: ValueKey(posts[i].id),
              post: posts[i],
              onDeleted: onRefresh,
            ),
          ),
        );
      },
    );
  }
}
