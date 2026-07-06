/// Centralised route path constants and path builders.
///
/// Path templates (with `:param`) are used when registering routes; the
/// `*Path(...)` helpers build concrete locations for navigation.
class Routes {
  Routes._();

  // ---- Auth / onboarding ----
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String register = '/register';

  // ---- Main shell tabs ----
  static const String home = '/home';
  static const String search = '/search';
  static const String bookings = '/bookings';
  static const String chat = '/chat';
  static const String profile = '/profile';
  static const String swap = '/swap';

  // ---- Discovery ----
  static const String category = '/category/:slug';
  static String categoryPath(String slug) => '/category/$slug';

  static const String companion = '/companion/:id';
  static String companionPath(String id) => '/companion/$id';

  static const String reviews = '/reviews/:companionId';
  static String reviewsPath(String companionId) => '/reviews/$companionId';

  // ---- Booking + payment ----
  static const String booking = '/booking/:companionId';
  static String bookingPath(String companionId) => '/booking/$companionId';

  static const String payment = '/payment/:bookingId';
  static String paymentPath(String bookingId) => '/payment/$bookingId';

  static const String bookingDetail = '/booking-detail/:id';
  static String bookingDetailPath(String id) => '/booking-detail/$id';

  // ---- Live location tracking (booking-scoped) ----
  static const String liveTracking = '/track/:bookingId';
  static String liveTrackingPath(String bookingId) => '/track/$bookingId';

  // ---- Chat ----
  static const String chatThread = '/chat/:conversationId';
  static String chatThreadPath(String conversationId) =>
      '/chat/$conversationId';

  // ---- Voice/video call (requires CallScreenArgs via `extra`) ----
  static const String call = '/call';

  // ---- Social feed (Instagram-style posts) ----
  static const String feed = '/feed';
  static const String postCompose = '/post/new';
  static const String postDetail = '/post/:id';
  static String postPath(String id) => '/post/$id';

  // ---- Wallet / notifications ----
  static const String wallet = '/wallet';
  static const String notifications = '/notifications';

  // ---- Settings / support ----
  static const String settings = '/settings';
  static const String support = '/support';
  static const String supportChat = '/support-chat';

  // ---- Companion-side ----
  static const String companionDashboard = '/companion-dashboard';
  static const String companionOnboarding = '/companion-onboarding';

  /// Routes accessible without authentication (the auth redirect allow-list).
  static const Set<String> publicRoutes = {
    splash,
    onboarding,
    login,
    otp,
    register,
  };

  /// True if [location] starts with one of the public route prefixes.
  static bool isPublic(String location) {
    final path = location.split('?').first;
    for (final r in publicRoutes) {
      if (path == r || path.startsWith('$r/')) return true;
    }
    return false;
  }
}
