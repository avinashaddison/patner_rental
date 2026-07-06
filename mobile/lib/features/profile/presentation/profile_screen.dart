import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/models/user_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/bookings/application/bookings_providers.dart';
import 'package:companion_ranchi/features/profile/application/profile_providers.dart';
import 'package:companion_ranchi/features/profile/presentation/edit_profile_sheet.dart';
import 'package:companion_ranchi/features/wallet/application/wallet_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Soft pink page background the profile cards rest on.
const Color _kPageBg = Color(0xFFFFF3F7);

/// The signed-in user's account hub: identity, referral card (₹100 reward),
/// quick links (wallet, bookings, settings, support), companion entry point and
/// sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const EmptyView(
          icon: Icons.person_off_rounded,
          title: 'Not signed in',
          message: 'Sign in to view your profile.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: _kPageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _ProfileHeader(user: user),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _HeaderStats(user: user),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _ReferralCard(user: user),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (user.isCompanion)
            _NavTile(
              icon: Icons.dashboard_customize_rounded,
              title: 'Companion Dashboard',
              subtitle: 'Earnings, bookings and your profile',
              onTap: () => context.push(Routes.companionDashboard),
              highlight: true,
            )
          else
            _NavTile(
              icon: Icons.volunteer_activism_rounded,
              title: 'Become a Companion',
              subtitle: 'Earn by offering your company for social activities',
              onTap: () => context.push(Routes.companionOnboarding),
              highlight: true,
            ),
          const Divider(height: 24),
          _NavTile(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Wallet',
            subtitle: 'Balance, transactions and payouts',
            onTap: () => context.push(Routes.wallet),
          ),
          _NavTile(
            icon: Icons.calendar_month_rounded,
            title: 'My Bookings',
            subtitle: 'Upcoming and past meetings',
            onTap: () => context.push(Routes.bookings),
          ),
          _NavTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            onTap: () => context.push(Routes.notifications),
          ),
          const Divider(height: 24),
          _NavTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () => context.push(Routes.settings),
          ),
          _NavTile(
            icon: Icons.support_agent_rounded,
            title: 'Help & Support',
            onTap: () => context.push(Routes.support),
          ),
          const Divider(height: 24),
          _NavTile(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            destructive: true,
            onTap: () => _confirmSignOut(context, ref),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '${AppConstants.appName} • v1.0.0',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to verify your number again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go(Routes.login);
  }
}

// ---------------------------------------------------------------------------
// Header with avatar, name, mobile and edit / change-photo actions
// ---------------------------------------------------------------------------

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editState = ref.watch(profileEditControllerProvider);
    final isUploading = editState.isLoading;

    final email = user.email;
    final showSeal = user.isMobileVerified || (email != null && email.isNotEmpty);
    final hasEmail = email != null && email.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar + camera badge.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    photoUrl: user.profilePhotoUrl,
                    name: user.fullName,
                    radius: 38,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(
                        side: BorderSide(color: Colors.white, width: 2.5),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap:
                            isUploading ? null : () => _changePhoto(context, ref),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: isUploading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_rounded,
                                  size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name · username · chips · email.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (showSeal) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified,
                              size: 18, color: AppColors.primary),
                        ],
                      ],
                    ),
                    if (user.username != null && user.username!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InfoChip(
                          label: user.isCompanion ? 'Companion' : 'Customer',
                          icon: user.isCompanion
                              ? Icons.verified_user_rounded
                              : Icons.person_rounded,
                        ),
                        if (user.city != null && user.city!.isNotEmpty)
                          _InfoChip(
                            label: user.city!,
                            icon: Icons.location_on_rounded,
                          ),
                      ],
                    ),
                    if (hasEmail) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.mail_outline_rounded,
                              size: 15, color: AppColors.inkMuted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ProfileActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit profile',
                  filled: true,
                  onTap: () => _editProfile(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileActionButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Add funds',
                  filled: false,
                  onTap: () => context.push(Routes.wallet),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditProfileSheet(user: user),
    );
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the photo picker.')),
        );
      }
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final user = await ref
        .read(profileEditControllerProvider.notifier)
        .updateAvatar(
          bytes: bytes,
          fileName: file.name,
          contentType: _contentTypeFor(file.name),
        );

    if (!context.mounted) return;
    if (user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } else {
      final error = ref.read(profileEditControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not update your photo.',
          ),
        ),
      );
    }
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}

// ---------------------------------------------------------------------------
// Glanceable stats strip (wallet balance · bookings · member since) shown as a
// white card resting on the gradient header.
// ---------------------------------------------------------------------------

class _HeaderStats extends ConsumerWidget {
  const _HeaderStats({required this.user});

  final UserModel user;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletSummaryProvider);
    final bookings = ref.watch(myBookingsProvider);

    final balance = wallet.valueOrNull;
    final walletValue =
        balance == null ? '—' : '₹${balance.balance.toStringAsFixed(0)}';
    final bookingsValue =
        bookings.valueOrNull == null ? '—' : '${bookings.valueOrNull!.length}';
    final created = user.createdAt;
    final memberValue = created == null
        ? '—'
        : '${_months[created.month - 1]} ${created.year}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatCell(
              icon: Icons.account_balance_wallet_rounded,
              value: walletValue,
              label: 'Wallet Balance',
              action: _StatLink(
                label: 'View wallet',
                onTap: () => context.push(Routes.wallet),
              ),
            ),
            const _StatDivider(),
            _StatCell(
              icon: Icons.calendar_month_rounded,
              value: bookingsValue,
              label: 'Bookings',
              action: _StatLink(
                label: 'View bookings',
                onTap: () => context.push(Routes.bookings),
              ),
            ),
            const _StatDivider(),
            _StatCell(
              icon: Icons.favorite_rounded,
              value: memberValue,
              label: 'Member since',
              action: const _MemberBadge(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
    required this.action,
  });

  final IconData icon;
  final String value;
  final String label;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            action,
          ],
        ),
      ),
    );
  }
}

/// Tappable "View wallet →" style link beneath a stat.
class _StatLink extends StatelessWidget {
  const _StatLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward_rounded,
                size: 11, color: AppColors.primaryDark),
          ],
        ),
      ),
    );
  }
}

/// Soft pink "Member" badge (crown) shown under the member-since stat.
class _MemberBadge extends StatelessWidget {
  const _MemberBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded,
              size: 12, color: AppColors.primaryDark),
          SizedBox(width: 3),
          Text(
            'Member',
            style: TextStyle(
              color: AppColors.primaryDark,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: AppColors.line);
  }
}

/// Light chip (role, city) used inside the white identity card.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact profile action button that fills its (Expanded) width. [filled] =
/// pink gradient (primary action); otherwise a soft pink-tinted tonal button.
class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.primaryDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? AppGradients.primary : null,
          color: filled ? null : AppColors.field,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Referral card (₹100 reward copy + share code)
// ---------------------------------------------------------------------------

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(referralSummaryProvider);
    // Fall back to the user's own referralCode while the summary loads.
    final code = summary.valueOrNull?.referralCode ?? user.referralCode ?? '';
    final totalReferred = summary.valueOrNull?.totalReferred ?? 0;
    final totalCompleted = summary.valueOrNull?.totalCompleted ?? 0;
    final totalEarned = summary.valueOrNull?.totalEarned ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Refer & earn ₹100',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Invite a friend. You get ₹100 in your wallet after their first '
            'completed booking.',
            style:
                TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (code.isEmpty)
            const Text(
              'Your referral code will appear here shortly.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: AppColors.field,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR CODE',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyCode(context, code),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _ReferralStat(
                value: '$totalReferred',
                label: 'Invited',
              ),
              const SizedBox(width: 20),
              _ReferralStat(
                value: '$totalCompleted',
                label: 'Joined',
              ),
              const SizedBox(width: 20),
              _ReferralStat(
                value: '₹${totalEarned.toStringAsFixed(0)}',
                label: 'Earned',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied to clipboard.')),
    );
  }
}

class _ReferralStat extends StatelessWidget {
  const _ReferralStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation tile
// ---------------------------------------------------------------------------

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.highlight = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool highlight;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.danger
        : highlight
            ? AppColors.primary
            : null;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (color ?? AppColors.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Icon(icon, color: color ?? AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: destructive ? AppColors.danger : null,
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: destructive
          ? null
          : const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
    );
  }
}
