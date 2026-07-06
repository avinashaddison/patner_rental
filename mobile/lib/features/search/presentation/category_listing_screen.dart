import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/search/application/category_listing_controller.dart';
import 'package:companion_ranchi/features/search/application/search_controller.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Companions filtered to a single activity category slug
/// (`GET /companions?category=<slug>`). Reuses the search pipeline for paging.
class CategoryListingScreen extends ConsumerStatefulWidget {
  const CategoryListingScreen({super.key, required this.slug});

  /// Category slug from the route, e.g. `coffee-partner`.
  final String slug;

  @override
  ConsumerState<CategoryListingScreen> createState() =>
      _CategoryListingScreenState();
}

class _CategoryListingScreenState extends ConsumerState<CategoryListingScreen> {
  final _scrollController = ScrollController();

  CategoryListingArgs get _args => CategoryListingArgs(slug: widget.slug);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(categoryListingControllerProvider(_args).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = AppCategories.bySlug(widget.slug);
    final name = def?.name ?? widget.slug;
    final state = ref.watch(categoryListingControllerProvider(_args));
    final notifier =
        ref.read(categoryListingControllerProvider(_args).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (def != null) ...[
              Text(def.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: _buildBody(context, state, notifier, def?.description),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state,
    CategoryListingController notifier,
    String? description,
  ) {
    if (state.isLoading) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: _gridDelegate(context),
        itemCount: 6,
        itemBuilder: (_, __) => const CompanionCardSkeleton(),
      );
    }

    if (state.error != null) {
      return ErrorView(error: state.error, onRetry: notifier.load);
    }

    if (state.companions.isEmpty) {
      return EmptyView(
        icon: Icons.event_busy_rounded,
        title: 'No companions yet',
        message: 'No one is offering this activity right now. '
            'Browse other categories or search instead.',
        actionLabel: 'Browse all',
        onAction: () => context.go(Routes.search),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.load,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (description != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  description,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.inkMuted),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate(context),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final c = state.companions[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FeaturedCompanionCard(
                        companion: c,
                        width: double.infinity,
                        onTap: () => context.push(Routes.companionPath(c.id)),
                        onBook: () => context.push(Routes.companionPath(c.id)),
                      ),
                    ],
                  );
                },
                childCount: state.companions.length,
              ),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // Aspect ratio computed so the cell matches the card's natural height:
  // 1.5px gradient border + a 1.1 photo + ~143 body (name/price + inset pill),
  // plus a little slack so the CTA never overflows the tile.
  SliverGridDelegateWithFixedCrossAxisCount _gridDelegate(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cell = (w - 2 * AppSpacing.lg - AppSpacing.md) / 2;
    final height = cell / 1.1 + 147;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: cell / height,
    );
  }
}
