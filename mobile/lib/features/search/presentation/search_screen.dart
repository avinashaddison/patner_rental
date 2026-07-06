import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/search/application/search_controller.dart';
import 'package:companion_ranchi/features/search/data/search_repository.dart';
import 'package:companion_ranchi/features/search/presentation/search_filter_sheet.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Search + filters over `GET /companions`: a query bar, a horizontal category
/// strip, a filters entry (rate/rating/online/city) and an infinite-scroll grid
/// of [CompanionCard].
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Kick off an initial unfiltered listing after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialised) {
        _initialised = true;
        final state = ref.read(searchControllerProvider);
        if (!state.hasSearched) {
          ref.read(searchControllerProvider.notifier).search();
        } else {
          _queryController.text = state.filters.query ?? '';
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      ref.read(searchControllerProvider.notifier).setQuery(value);
    });
  }

  Future<void> _openFilters() async {
    final current = ref.read(searchControllerProvider).filters;
    final updated = await showModalBottomSheet<CompanionSearchFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchFilterSheet(initial: current),
    );
    if (updated != null) {
      await ref.read(searchControllerProvider.notifier).applyFilters(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final activeFilterCount = _activeFilterCount(state.filters);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a companion'),
        titleSpacing: AppSpacing.lg,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _queryController,
                    hint: 'Search by name or interest',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _queryController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _queryController.clear();
                              ref
                                  .read(searchControllerProvider.notifier)
                                  .setQuery('');
                              setState(() {});
                            },
                          ),
                    textInputAction: TextInputAction.search,
                    onChanged: (v) {
                      setState(() {});
                      _onQueryChanged(v);
                    },
                    onSubmitted: (v) => ref
                        .read(searchControllerProvider.notifier)
                        .setQuery(v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterButton(
                  count: activeFilterCount,
                  onTap: _openFilters,
                ),
              ],
            ),
          ),
          _CategoryStrip(
            selected: state.filters.category,
            onSelected: (slug) {
              ref.read(searchControllerProvider.notifier).setCategory(slug);
            },
          ),
          _ResultsHeader(state: state),
          Expanded(child: _ResultsBody(scrollController: _scrollController)),
        ],
      ),
    );
  }

  int _activeFilterCount(CompanionSearchFilters f) {
    var n = 0;
    if (f.city != null) n++;
    if (f.minRate != null || f.maxRate != null) n++;
    if (f.minRating != null) n++;
    if (f.onlineOnly) n++;
    if (f.featuredOnly) n++;
    if (f.sort != null) n++;
    return n;
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppColors.danger,
      label: Text('$count'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5C8A), Color(0xFFFF3B6B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const SizedBox(
              width: 54,
              height: 54,
              child: Icon(Icons.tune_rounded, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    const categories = AppCategories.all;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Center(
              child: CategoryChip(
                label: 'All',
                icon: Icons.apps_rounded,
                selected: selected == null,
                onTap: () => onSelected(null),
              ),
            );
          }
          final c = categories[i - 1];
          final isSelected = selected == c.slug;
          return Center(
            child: CategoryChip(
              label: c.name,
              emoji: c.emoji,
              selected: isSelected,
              onTap: () => onSelected(isSelected ? null : c.slug),
            ),
          );
        },
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading || !state.hasSearched || state.error != null) {
      return const SizedBox(height: AppSpacing.sm);
    }
    final count = state.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          count == 1 ? '1 companion found' : '$count companions found',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ResultsBody extends ConsumerWidget {
  const _ResultsBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchControllerProvider);
    final notifier = ref.read(searchControllerProvider.notifier);

    if (state.isLoading) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: _gridDelegate(context),
        itemCount: 6,
        itemBuilder: (_, __) => const CompanionCardSkeleton(),
      );
    }

    if (state.error != null) {
      return ErrorView(
        error: state.error,
        onRetry: notifier.search,
      );
    }

    if (state.companions.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: 'No companions match',
        message:
            'Try removing some filters or searching a different activity.',
        actionLabel: state.filters.hasActiveFilters ? 'Clear filters' : null,
        onAction:
            state.filters.hasActiveFilters ? () => notifier.clear() : null,
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.search,
      child: GridView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: _gridDelegate(context),
        itemCount: state.companions.length + (state.isLoadingMore ? 2 : 0),
        itemBuilder: (context, i) {
          if (i >= state.companions.length) {
            return const CompanionCardSkeleton();
          }
          final c = state.companions[i];
          // Stretch column lets the card keep its natural height (footer flush)
          // while the leftover tile space falls below it as transparent spacing.
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
