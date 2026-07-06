import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/router/main_shell.dart';
import 'package:companion_ranchi/core/router/routes.dart';

// Auth / onboarding
import 'package:companion_ranchi/features/onboarding/presentation/splash_screen.dart';
import 'package:companion_ranchi/features/onboarding/presentation/onboarding_screen.dart';
import 'package:companion_ranchi/features/auth/presentation/login_screen.dart';
import 'package:companion_ranchi/features/auth/presentation/otp_screen.dart';
import 'package:companion_ranchi/features/auth/presentation/register_screen.dart';

// Tabs
import 'package:companion_ranchi/features/home/presentation/home_screen.dart';
import 'package:companion_ranchi/features/search/presentation/search_screen.dart';
import 'package:companion_ranchi/features/bookings/presentation/my_bookings_screen.dart';
import 'package:companion_ranchi/features/chat/presentation/conversations_screen.dart';
import 'package:companion_ranchi/features/profile/presentation/profile_screen.dart';

// Discovery / detail
import 'package:companion_ranchi/features/search/presentation/category_listing_screen.dart';
import 'package:companion_ranchi/features/companion/presentation/companion_profile_screen.dart';
import 'package:companion_ranchi/features/reviews/presentation/reviews_screen.dart';

// Booking / payment
import 'package:companion_ranchi/features/booking/presentation/booking_flow_screen.dart';
import 'package:companion_ranchi/features/payment/presentation/payment_screen.dart';
import 'package:companion_ranchi/features/bookings/presentation/booking_detail_screen.dart';

// Chat thread
import 'package:companion_ranchi/features/chat/presentation/chat_screen.dart';

// Voice/video calls
import 'package:companion_ranchi/features/calls/presentation/call_screen.dart';

// Live location tracking
import 'package:companion_ranchi/features/tracking/presentation/live_tracking_screen.dart';

// Social feed
import 'package:companion_ranchi/features/feed/presentation/feed_screen.dart';
import 'package:companion_ranchi/features/feed/presentation/post_detail_screen.dart';
import 'package:companion_ranchi/features/feed/presentation/post_composer_screen.dart';
import 'package:companion_ranchi/features/feed/presentation/swap_screen.dart';

// Misc
import 'package:companion_ranchi/features/wallet/presentation/wallet_screen.dart';
import 'package:companion_ranchi/features/notifications/presentation/notifications_screen.dart';
import 'package:companion_ranchi/features/settings/presentation/settings_screen.dart';
import 'package:companion_ranchi/features/support/presentation/support_screen.dart';
import 'package:companion_ranchi/features/support/presentation/support_chat_screen.dart';
import 'package:companion_ranchi/features/companion_dashboard/presentation/companion_dashboard_screen.dart';
import 'package:companion_ranchi/features/companion_dashboard/presentation/companion_onboarding_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// A [Listenable] that notifies go_router whenever the auth state flips between
/// authenticated and unauthenticated, triggering the redirect to re-run.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(
      authControllerProvider,
      (prev, next) {
        final was = prev?.valueOrNull != null;
        final now = next.valueOrNull != null;
        if (was != now) notifyListeners();
      },
    );
  }
}

/// The application router. Referenced by `app.dart` via `MaterialApp.router`.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(currentUserProvider) != null;
      final location = state.matchedLocation;
      final onPublic = Routes.isPublic(location);
      final onSplash = location == Routes.splash;

      // While on splash, let the splash screen route once bootstrapping ends.
      if (onSplash) return null;

      // Unauthenticated users may only see public (auth/onboarding) routes.
      if (!loggedIn && !onPublic) return Routes.login;

      // Authenticated users should not sit on login/otp/onboarding.
      if (loggedIn &&
          (location == Routes.login ||
              location == Routes.otp ||
              location == Routes.onboarding)) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      // ---- Public / auth ----
      GoRoute(
        path: Routes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (_, __) => const OtpScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, __) => const RegisterScreen(),
      ),

      // ---- Main shell with bottom navigation ----
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Home branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, __) => const HomeScreen(),
              ),
            ],
          ),
          // Search branch (+ category listing nested for stack retention)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.search,
                builder: (_, __) => const SearchScreen(),
                routes: [
                  GoRoute(
                    path: 'category/:slug',
                    builder: (_, state) => CategoryListingScreen(
                      slug: state.pathParameters['slug'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Bookings branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.bookings,
                builder: (_, __) => const MyBookingsScreen(),
              ),
            ],
          ),
          // Chat branch (list + thread)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.chat,
                builder: (_, __) => const ConversationsScreen(),
                routes: [
                  GoRoute(
                    path: ':conversationId',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => ChatScreen(
                      conversationId:
                          state.pathParameters['conversationId'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Profile branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ---- Full-screen routes (pushed above the shell) ----
      GoRoute(
        path: Routes.call,
        parentNavigatorKey: _rootKey,
        builder: (_, state) {
          final callArgs = state.extra;
          if (callArgs is! CallScreenArgs) {
            // Deep-linked or restored without args — nothing to show.
            return const Scaffold(body: SizedBox.shrink());
          }
          return CallScreen(args: callArgs);
        },
      ),
      GoRoute(
        path: Routes.category,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CategoryListingScreen(
          slug: state.pathParameters['slug'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.companion,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CompanionProfileScreen(
          companionId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.reviews,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ReviewsScreen(
          companionId: state.pathParameters['companionId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.booking,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => BookingFlowScreen(
          companionId: state.pathParameters['companionId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.payment,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => PaymentScreen(
          bookingId: state.pathParameters['bookingId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.bookingDetail,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => BookingDetailScreen(
          bookingId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.liveTracking,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => LiveTrackingScreen(
          bookingId: state.pathParameters['bookingId'] ?? '',
          peerName: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: Routes.wallet,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WalletScreen(),
      ),
      // Swap — immersive full-screen vertical discovery feed. Pushed on the
      // root navigator (above the shell) so the bottom navigation bar is hidden
      // while swiping. Reached from the "Swap" item in the bottom nav.
      GoRoute(
        path: Routes.swap,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SwapScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const NotificationsScreen(),
      ),
      // ---- Social feed (static /post/new before dynamic /post/:id) ----
      GoRoute(
        path: Routes.feed,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const FeedScreen(),
      ),
      GoRoute(
        path: Routes.postCompose,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PostComposerScreen(),
      ),
      GoRoute(
        path: Routes.postDetail,
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            PostDetailScreen(postId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.support,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SupportScreen(),
      ),
      GoRoute(
        path: Routes.supportChat,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SupportChatScreen(),
      ),
      GoRoute(
        path: Routes.companionDashboard,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CompanionDashboardScreen(),
      ),
      GoRoute(
        path: Routes.companionOnboarding,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CompanionOnboardingScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Text('No route for ${state.uri}'),
      ),
    ),
  );
});
