import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/booking_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/core/models/post_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/formatters.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/booking_action_controller.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/companion_dashboard_providers.dart';
import 'package:companion_ranchi/features/companion_dashboard/application/online_controller.dart';
import 'package:companion_ranchi/features/companion_dashboard/data/companion_dashboard_models.dart';
import 'package:companion_ranchi/features/companion_dashboard/presentation/availability_manager_sheet.dart';
import 'package:companion_ranchi/features/bookings/presentation/widgets/start_code_dialog.dart';
import 'package:companion_ranchi/features/companion_dashboard/presentation/widgets/incoming_booking_card.dart';
import 'package:companion_ranchi/features/companion_dashboard/presentation/widgets/meeting_area_card.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/features/feed/data/feed_repository.dart';
import 'package:companion_ranchi/features/profile/application/profile_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Companion-side home: earnings/ratings cards, online toggle, availability
/// manager, incoming booking requests (accept/reject) and upcoming bookings.
/// Backed by `/companion/dashboard`, `/companion/earnings`,
/// `/companion/bookings`, and the `/companions/me/*` mutation endpoints.
class CompanionDashboardScreen extends ConsumerWidget {
  const CompanionDashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    invalidateCompanionDashboardFromWidget(ref);
    ref.invalidate(myCompanionProfileProvider);
    await ref.read(companionDashboardProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myCompanionProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Wallet',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => context.push(Routes.wallet),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const LoadingView(message: 'Loading your dashboard…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(myCompanionProfileProvider),
        ),
        data: (profile) {
          if (profile == null) {
            return _NotACompanion(
              onStart: () => context.push(Routes.companionOnboarding),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: _DashboardBody(profile: profile),
          );
        },
      ),
    );
  }
}

class _NotACompanion extends StatelessWidget {
  const _NotACompanion({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.badge_outlined, size: 64, color: AppColors.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Become a Companion',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set up your profile, rates and complete KYC to start earning by '
              'offering companionship for coffee, movies, events and city tours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: 'Get started',
              icon: Icons.arrow_forward_rounded,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.profile});

  final CompanionModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(companionDashboardProvider);

    // Ordered by what a companion needs first: status → visibility → money →
    // the task that unblocks bookings (availability) → actual bookings →
    // logistics (meeting area) → social content last.
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        _Header(profile: profile),
        const SizedBox(height: AppSpacing.sm),
        _PendingApprovalBanner(status: profile.status),
        _OnlineToggleCard(profile: profile),
        dashboardAsync.when(
          loading: () => const _EarningsHeroSkeleton(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(companionDashboardProvider),
            ),
          ),
          data: (d) => _EarningsHeroCard(dashboard: d),
        ),
        _AvailabilityCard(profile: profile),
        const _PendingRequestsSection(),
        const _UpcomingBookingsSection(),
        MeetingAreaCard(profile: profile),
        const SectionHeader(title: 'My Posts'),
        _ContentSection(profile: profile),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final CompanionModel profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          _EditableAvatar(fallbackName: profile.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (profile.ratingCount > 0)
                      RatingStars(
                        rating: profile.rating,
                        count: profile.ratingCount,
                        size: 14,
                      )
                    else
                      // A brand-new companion has no ratings yet — "⭐ 0.0"
                      // reads as a terrible score, so show a friendly badge.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: const Text(
                          '✦ New',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (profile.isVerified)
                      const VerifiedBadge(compact: true),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              Formatters.ratePerHour(profile.hourlyRate),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable avatar with a camera badge — lets the companion change their profile
/// photo right from the dashboard (reuses the standard avatar upload flow).
class _EditableAvatar extends ConsumerStatefulWidget {
  const _EditableAvatar({required this.fallbackName});

  final String fallbackName;

  @override
  ConsumerState<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends ConsumerState<_EditableAvatar> {
  bool _busy = false;

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _contentTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _change() async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
    } catch (_) {
      _snack('Could not open the photo picker.');
      return;
    }
    if (file == null) return;
    setState(() => _busy = true);
    final bytes = await file.readAsBytes();
    final user = await ref.read(profileEditControllerProvider.notifier).updateAvatar(
          bytes: bytes,
          fileName: file.name,
          contentType: _contentTypeFor(file.name),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (user != null) {
      ref.invalidate(myCompanionProfileProvider);
      _snack('Profile photo updated.');
    } else {
      final e = ref.read(profileEditControllerProvider).error;
      _snack(e is ApiException ? e.message : 'Could not update your photo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return GestureDetector(
      onTap: _busy ? null : _change,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UserAvatar(
            photoUrl: user?.profilePhotoUrl,
            name: widget.fallbackName,
            radius: 28,
          ),
          if (_busy)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Companion content management: post/follower/following counts, a "new post"
/// button, and the companion's own posts grid with delete.
class _ContentSection extends ConsumerWidget {
  const _ContentSection({required this.profile});

  final CompanionModel profile;

  Future<void> _deletePost(BuildContext context, WidgetRef ref, PostModel post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
          'This permanently removes the post along with its likes and comments.',
        ),
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
      invalidateFeeds(ref, companionId: profile.id);
      ref.invalidate(myCompanionProfileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is ApiException ? e.message : 'Could not delete the post.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(companionPostsProvider(profile.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Row(
              children: [
                _CountCell(value: '${profile.postCount}', label: 'Posts'),
                _countDivider(),
                _CountCell(value: '${profile.followerCount}', label: 'Followers'),
                _countDivider(),
                _CountCell(value: '${profile.followingCount}', label: 'Following'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Outline, not gradient — posts are a secondary feature and the
          // gradient CTA is reserved for the screen's primary action.
          AppButton.outline(
            label: 'Upload new post',
            icon: Icons.add_a_photo_rounded,
            onPressed: () => context.push(Routes.postCompose),
          ),
          const SizedBox(height: AppSpacing.md),
          postsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            ),
            error: (_, __) => TextButton.icon(
              onPressed: () => ref.invalidate(companionPostsProvider(profile.id)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry loading posts'),
            ),
            data: (posts) {
              if (posts.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border: Border.all(color: AppColors.fieldBorder),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 20,
                        color: AppColors.inkMuted,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No posts yet. Share a photo to appear in customer feeds.',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                children: [
                  for (final p in posts)
                    _MyPostTile(post: p, onDelete: () => _deletePost(context, ref, p)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _countDivider() => Container(width: 1, height: 30, color: AppColors.line);
}

class _CountCell extends StatelessWidget {
  const _CountCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MyPostTile extends StatelessWidget {
  const _MyPostTile({required this.post, required this.onDelete});

  final PostModel post;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final url = post.images.isNotEmpty ? post.images.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => context.push(Routes.postPath(post.id)),
            child: url != null
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(color: AppColors.field),
                    errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.field),
                  )
                : const ColoredBox(color: AppColors.field),
          ),
          if (post.images.length > 1)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.collections_rounded, size: 15, color: Colors.white),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingApprovalBanner extends StatelessWidget {
  const _PendingApprovalBanner({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    if (status == null || status == 'APPROVED') {
      return const SizedBox.shrink();
    }
    final (String text, Color color, IconData icon) = switch (status) {
      'PENDING' => (
          'Your profile is under review. You will be notified once approved.',
          AppColors.warning,
          Icons.hourglass_top_rounded,
        ),
      'REJECTED' => (
          'Your application was rejected. Please review your details and KYC.',
          AppColors.danger,
          Icons.cancel_outlined,
        ),
      'SUSPENDED' => (
          'Your profile is suspended. Contact support for assistance.',
          AppColors.danger,
          Icons.pause_circle_outline_rounded,
        ),
      _ => ('Profile status: $status', AppColors.inkMuted, Icons.info_outline),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineToggleCard extends ConsumerWidget {
  const _OnlineToggleCard({required this.profile});

  final CompanionModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seed the controller from the loaded profile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(onlineControllerProvider.notifier).hydrate(profile.isOnline);
    });
    final online = ref.watch(onlineControllerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              OnlineDot(isOnline: online.isOnline, withBorder: false),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online.isOnline ? 'You are online' : 'You are offline',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      online.isOnline
                          ? 'Visible to customers searching now.'
                          : 'Turn on to appear in live search.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (online.isSaving)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Switch(
                  value: online.isOnline,
                  onChanged: (v) async {
                    try {
                      await ref
                          .read(onlineControllerProvider.notifier)
                          .toggle(v);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update status.'),
                          ),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.profile});

  final CompanionModel profile;

  @override
  Widget build(BuildContext context) {
    final count = profile.availability.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Card(
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.event_available_outlined,
                color: AppColors.primary),
          ),
          title: const Text(
            'Weekly availability',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            count == 0
                ? 'No windows set — add times to receive bookings.'
                : '$count time window${count == 1 ? '' : 's'} set',
          ),
          // With no windows set, this is the task blocking bookings — promote
          // the affordance from a chevron to an explicit action chip.
          trailing: count == 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: const Text(
                    'Add times',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: () => AvailabilityManagerSheet.show(
            context,
            initial: profile.availability,
          ),
        ),
      ),
    );
  }
}

/// The money card — a deep plum gradient hero showing total earnings with
/// pending/withdrawn beneath. Tapping anywhere opens the wallet.
class _EarningsHeroCard extends StatelessWidget {
  const _EarningsHeroCard({required this.dashboard});

  final CompanionDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: () => context.push(Routes.wallet),
          child: Ink(
            decoration: BoxDecoration(
              // "Green = money" — shared emerald gradient with the wallet hero.
              gradient: AppGradients.money,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.money.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'TOTAL EARNINGS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white60,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Wallet',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.moneySmart(dashboard.totalEarnings),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroMiniStat(
                          label: 'Pending',
                          value: Formatters.moneySmart(dashboard.pendingEarnings),
                          dotColor: const Color(0xFFFFC24D),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white12,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _HeroMiniStat(
                          label: 'Withdrawn',
                          value: Formatters.moneySmart(dashboard.withdrawnEarnings),
                          dotColor: const Color(0xFF6EE7A0),
                        ),
                      ),
                    ],
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

class _HeroMiniStat extends StatelessWidget {
  const _HeroMiniStat({
    required this.label,
    required this.value,
    required this.dotColor,
  });

  final String label;
  final String value;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EarningsHeroSkeleton extends StatelessWidget {
  const _EarningsHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: ShimmerBox(height: 148, radius: AppSpacing.radiusLg),
    );
  }
}

class _PendingRequestsSection extends ConsumerWidget {
  const _PendingRequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(companionPendingRequestsProvider);

    return requestsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(companionPendingRequestsProvider),
        ),
      ),
      data: (requests) {
        if (requests.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Booking requests',
              subtitle: '${requests.length} awaiting your response',
            ),
            for (final b in requests)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _BookingRow(booking: b),
              ),
          ],
        );
      },
    );
  }
}

class _UpcomingBookingsSection extends ConsumerWidget {
  const _UpcomingBookingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(companionUpcomingBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(companionUpcomingBookingsProvider),
        ),
      ),
      data: (bookings) {
        // Exclude the still-pending ones already shown in requests.
        final upcoming =
            bookings.where((b) => b.status != BookingStatus.pending).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Upcoming bookings'),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: EmptyView(
                  icon: Icons.event_busy_outlined,
                  title: 'No upcoming bookings',
                  message:
                      'Accepted bookings will appear here. Stay online and keep '
                      'your availability up to date.',
                ),
              )
            else
              for (final b in upcoming)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: _BookingRow(booking: b),
                ),
          ],
        );
      },
    );
  }
}

/// A single booking row wired to the action controller.
class _BookingRow extends ConsumerWidget {
  const _BookingRow({required this.booking});

  final BookingModel booking;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    BookingAction action,
  ) async {
    // Starting requires the customer's 6-digit code → dedicated retry dialog.
    if (action == BookingAction.start) {
      await _startWithCode(context, ref);
      return;
    }

    // Confirm destructive/irreversible actions.
    if (action == BookingAction.reject || action == BookingAction.complete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            action == BookingAction.reject
                ? 'Reject booking?'
                : 'Mark as complete?',
          ),
          content: Text(
            action == BookingAction.reject
                ? 'The customer will be notified and refunded if they paid.'
                : 'Confirm the meeting is finished. Your payout will be '
                    'credited to your wallet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                action == BookingAction.reject ? 'Reject' : 'Complete',
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await ref
          .read(bookingActionControllerProvider.notifier)
          .run(booking.id, action);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_successMessage(action))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e))),
        );
      }
    }
  }

  /// Start flow: collect the customer's 6-digit code, then run the start action.
  /// The dialog stays open on a wrong code, surfacing the exact server message.
  Future<void> _startWithCode(BuildContext context, WidgetRef ref) async {
    final started = await showStartCodeDialog(
      context,
      onSubmit: (code) async {
        try {
          await ref
              .read(bookingActionControllerProvider.notifier)
              .run(booking.id, BookingAction.start, code: code);
          return null; // success
        } catch (e) {
          return _errorMessage(e);
        }
      },
    );
    if (started && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting started.')),
      );
    }
  }

  String _successMessage(BookingAction action) {
    switch (action) {
      case BookingAction.accept:
        return 'Booking accepted.';
      case BookingAction.reject:
        return 'Booking rejected.';
      case BookingAction.start:
        return 'Meeting started.';
      case BookingAction.complete:
        return 'Booking completed — payout credited.';
    }
  }

  String _errorMessage(Object e) {
    final s = e.toString();
    final i = s.indexOf(': ');
    return i >= 0 && i < s.length - 2 ? s.substring(i + 2) : s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busyId = ref.watch(bookingActionControllerProvider);
    final isBusy = busyId == booking.id;

    return IncomingBookingCard(
      booking: booking,
      isBusy: isBusy,
      onTap: () => context.push(Routes.bookingDetailPath(booking.id)),
      onAccept: () => _act(context, ref, BookingAction.accept),
      onReject: () => _act(context, ref, BookingAction.reject),
      onStart: () => _act(context, ref, BookingAction.start),
      onComplete: () => _act(context, ref, BookingAction.complete),
    );
  }
}
