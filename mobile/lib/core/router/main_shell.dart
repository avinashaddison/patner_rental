import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/push/push_service.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/chat/application/conversations_controller.dart';

// Floating nav geometry.
const double _kBarHeight = 82;
const double _kFabSize = 44; // centre heart button diameter (sits in the pill)

/// Bottom-navigation shell wrapping the primary shell branches
/// (0 Home, 1 Search, 2 Bookings, 3 Chat, 4 Profile). Used as the `builder` of
/// the [StatefulShellRoute] so each branch keeps its own navigation stack.
///
/// Rendered as a FLOATING soft-pink pill. The centre "Booking" heart button
/// (white ring + glow) sits compact inside the pill with its label beneath.
/// The active tab shows a gradient icon, a small tagline under its label and
/// a sliding underline indicator at the pill
/// edge. The "Swap" item is NOT a shell branch — it pushes the immersive
/// full-screen discovery feed on the root navigator (so the bottom nav hides
/// while swiping). Wallet is likewise a root-pushed full-screen route (reached
/// from Profile / the companion dashboard), not a shell branch.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    // `initialLocation` true re-pops to the tab root when re-tapping the
    // active tab — standard marketplace UX.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The shell only exists while authenticated — the right moment to wire
    // push notifications (idempotent; no-op without google-services.json).
    ref.read(pushServiceProvider).start();

    final current = navigationShell.currentIndex;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Real unread-message count for the Chat tab (0 → badge hides).
    final unreadChat = ref.watch(totalUnreadChatProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        // Scaffold-coloured wrapper; padding makes the bar float.
        color: AppColors.scaffold,
        padding: EdgeInsets.fromLTRB(14, 8, 14, 10 + bottomInset),
        child: SizedBox(
          height: _kBarHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Soft-pink floating pill.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFFDFE), Color(0xFFFFE9F1)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.20),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
              ),
              // Tab items — centre slot carries the Booking labels under the FAB.
              Positioned.fill(
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: 'Home',
                      selected: current == 0,
                      onTap: () => _onTap(0),
                    ),
                    _NavItem(
                      icon: Icons.style_outlined,
                      selectedIcon: Icons.style_rounded,
                      label: 'Swap',
                      tagline: 'Discover',
                      // Pushed full-screen route, not a branch — never "active"
                      // in the bar (the bar is hidden while Swap is open).
                      selected: false,
                      onTap: () => context.push(Routes.swap),
                    ),
                    // Centre slot: compact heart button fully inside the
                    // pill, label beneath — same rhythm as the other tabs.
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CenterFab(onTap: () => _onTap(2)),
                          const SizedBox(height: 3),
                          const Text(
                            'Booking',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _NavItem(
                      // Bubble-with-dots, matching the reference chat glyph.
                      icon: Icons.textsms_outlined,
                      selectedIcon: Icons.textsms_rounded,
                      label: 'Chat',
                      selected: current == 3,
                      badgeCount: unreadChat,
                      onTap: () => _onTap(3),
                    ),
                    _NavItem(
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
                      label: 'Profile',
                      selected: current == 4,
                      onTap: () => _onTap(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.tagline,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  /// Outlined variant, shown when the tab is inactive.
  final IconData icon;

  /// Filled (rounded-family) variant, shown when the tab is active.
  final IconData selectedIcon;
  final String label;

  /// Tiny second line shown only while the tab is active ("Discover"…).
  /// Omit for tabs that should show just their label.
  final String? tagline;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.inkMuted;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon block — no highlight box; the gradient icon and the
                // underline carry the active state.
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
                  child: AnimatedScale(
                    scale: selected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Active icon wears the brand gradient (matches FAB).
                        if (selected)
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF6FA0), Color(0xFFE63B5E)],
                            ).createShader(bounds),
                            child: Icon(selectedIcon,
                                color: Colors.white, size: 23),
                          )
                        else
                          Icon(icon, color: color, size: 23),
                        if (badgeCount > 0)
                          Positioned(
                            top: -6,
                            right: -8,
                            child: Container(
                              constraints: const BoxConstraints(
                                  minWidth: 16, minHeight: 16),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(9),
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  '$badgeCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                if (selected && tagline != null) ...[
                  Text(
                    tagline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.85),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Keeps the tagline clear of the underline indicator.
                  const SizedBox(height: 7),
                ],
              ],
            ),
            // Gradient underline indicator that slides open on selection.
            // NOTE: the curve must not overshoot (no easeOutBack) — width
            // animating 26 -> 0 would dip NEGATIVE on the overshoot, which
            // is a layout error Flutter paints as a dark red band.
            Positioned(
              bottom: 5,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: selected ? 26 : 0,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6FA0), Color(0xFFE63B5E)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The emphasised centre "Booking" FAB: a lifted pink-gradient circle with a
/// thick white ring, glow and a filled white heart.
class _CenterFab extends StatelessWidget {
  const _CenterFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kFabSize,
      height: _kFabSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6FA0), Color(0xFFE63B5E)],
        ),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.40),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 21,
              ),
              // Tiny sparkle riding the heart's shoulder.
              Positioned(
                top: 8,
                right: 7,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white70,
                  size: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
