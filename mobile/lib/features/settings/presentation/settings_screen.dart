import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/theme/theme_provider.dart';
import 'package:companion_ranchi/features/settings/application/settings_providers.dart';
import 'package:companion_ranchi/features/settings/presentation/blocked_users_screen.dart';
import 'package:companion_ranchi/features/settings/presentation/legal_screen.dart';

/// App settings: appearance (theme), notification preferences, privacy (blocked
/// users), language, legal & safety, account info and sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    final language = ref.watch(languageProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // -- Appearance ----------------------------------------------------
          const _SectionLabel('Appearance'),
          _ThemeSelector(
            value: themeMode,
            onChanged: (m) =>
                ref.read(themeModeProvider.notifier).setMode(m),
          ),

          const Divider(height: 24),

          // -- Notifications -------------------------------------------------
          const _SectionLabel('Notifications'),
          SwitchListTile(
            title: const Text('Booking updates'),
            subtitle: const Text('Requests, confirmations and reminders'),
            secondary: const Icon(Icons.event_available_rounded),
            value: prefs.bookings,
            onChanged: (v) =>
                ref.read(notificationPrefsProvider.notifier).setBookings(v),
          ),
          SwitchListTile(
            title: const Text('Payments & wallet'),
            subtitle: const Text('Payments, refunds and payouts'),
            secondary: const Icon(Icons.account_balance_wallet_rounded),
            value: prefs.payments,
            onChanged: (v) =>
                ref.read(notificationPrefsProvider.notifier).setPayments(v),
          ),
          SwitchListTile(
            title: const Text('Chat messages'),
            subtitle: const Text('New messages from companions / customers'),
            secondary: const Icon(Icons.chat_bubble_outline_rounded),
            value: prefs.chat,
            onChanged: (v) =>
                ref.read(notificationPrefsProvider.notifier).setChat(v),
          ),
          SwitchListTile(
            title: const Text('Offers & referrals'),
            subtitle: const Text('Promotions and referral rewards'),
            secondary: const Icon(Icons.local_offer_rounded),
            value: prefs.promotions,
            onChanged: (v) =>
                ref.read(notificationPrefsProvider.notifier).setPromotions(v),
          ),

          const Divider(height: 24),

          // -- Privacy -------------------------------------------------------
          const _SectionLabel('Privacy'),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Blocked users'),
            subtitle: const Text('Manage people you have blocked'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),

          const Divider(height: 24),

          // -- Language ------------------------------------------------------
          const _SectionLabel('Language'),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: const Text('App language'),
            subtitle: Text(language),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickLanguage(context, ref, language),
          ),

          const Divider(height: 24),

          // -- Legal & Safety ------------------------------------------------
          const _SectionLabel('Legal & Safety'),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Community & Safety Guidelines'),
            subtitle: const Text('18+ only • companionship • public places'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLegal(context, LegalDocument.safety),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLegal(context, LegalDocument.terms),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLegal(context, LegalDocument.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Refund & Cancellation Policy'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLegal(context, LegalDocument.refund),
          ),

          const Divider(height: 24),

          // -- Support & Account --------------------------------------------
          const _SectionLabel('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(user?.fullName ?? 'Guest'),
            subtitle: Text(user?.mobileNumber ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.support),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: const Text('Rate the app'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _launch(
              context,
              'https://play.google.com/store/apps/details?id=com.companionranchi.app',
            ),
          ),

          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
            title: const Text(
              'Sign out',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () => _confirmSignOut(context, ref),
          ),

          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Version 1.0.0 (1)',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A companionship service. Not an escort or dating service.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Choose language',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              RadioGroup<String>(
                groupValue: current,
                onChanged: (v) => Navigator.pop(ctx, v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final lang in LanguageNotifier.supported)
                      RadioListTile<String>(
                        title: Text(lang),
                        value: lang,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await ref.read(languageProvider.notifier).setLanguage(selected);
      if (context.mounted && selected != 'English') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hindi support is rolling out soon.'),
          ),
        );
      }
    }
  }

  void _openLegal(BuildContext context, LegalDocument doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalScreen(document: doc)),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
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

/// Premium appearance selector — three rounded theme tiles in a gold-accented
/// card. Replaces the legacy [RadioListTile] group (no deprecated APIs).
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: isDark ? AppColors.darkLine : AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ThemeOption(
                icon: Icons.brightness_auto_rounded,
                label: 'System',
                selected: value == ThemeMode.system,
                onTap: () => onChanged(ThemeMode.system),
              ),
            ),
            Expanded(
              child: _ThemeOption(
                icon: Icons.light_mode_rounded,
                label: 'Light',
                selected: value == ThemeMode.light,
                onTap: () => onChanged(ThemeMode.light),
              ),
            ),
            Expanded(
              child: _ThemeOption(
                icon: Icons.dark_mode_rounded,
                label: 'Dark',
                selected: value == ThemeMode.dark,
                onTap: () => onChanged(ThemeMode.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkInkMuted
            : AppColors.inkMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.primary : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : muted,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
