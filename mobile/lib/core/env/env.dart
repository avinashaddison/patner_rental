/// Compile-time / runtime environment configuration for the app.
///
/// Values can be overridden at build time using `--dart-define`:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
///
/// Defaults target the Android emulator talking to a local backend
/// (host `10.0.2.2` maps to the developer machine's `localhost`).
class Env {
  Env._();

  /// Base host of the backend, WITHOUT the trailing `/api`.
  ///
  /// DEV DEFAULT = the dev machine's Wi-Fi/LAN IP. The phone reaches the
  /// backend directly over Wi-Fi, so connectivity NO LONGER depends on the
  /// fragile `adb reverse` USB tunnel (USB unplug/lock used to cause the
  /// recurring "couldn't load" errors). Backend binds 0.0.0.0:4000.
  ///
  /// If the dev machine's LAN IP changes (new Wi-Fi/hotspot), update the IP
  /// below OR override at build time:
  ///   flutter build apk --dart-define=API_BASE_URL=http://<ip>:4000 \
  ///                      --dart-define=SOCKET_URL=http://<ip>:4000
  /// Other targets: Android emulator `http://10.0.2.2:4000`,
  /// iOS sim/desktop `http://localhost:4000`,
  /// USB-only fallback (with `adb reverse tcp:4000 tcp:4000`) `http://localhost:4000`.
  static const String _apiHost = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.52.184.95:4000',
  );

  /// Socket.IO endpoint. Defaults to the same host as the API.
  static const String _socketHost = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.52.184.95:4000',
  );

  /// Full REST base, e.g. `http://10.0.2.2:4000/api`.
  static String get apiBaseUrl => '$_apiHost/api';

  /// Raw backend host (used for building absolute media URLs if needed).
  static String get apiHost => _apiHost;

  /// Socket.IO connection URL.
  static String get socketUrl => _socketHost;

  /// Razorpay public key id. Real value is returned by the backend per order;
  /// this is only a build-time fallback for the checkout widget.
  static const String razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_test_xxxxxxxx',
  );

  /// Mapbox public access token (`pk.*`) for the live-tracking map SDK.
  /// This is the CLIENT-side public token (safe to ship in the binary), but it
  /// is NOT hardcoded here so the repo stays clean of scanner-flagged tokens.
  /// Provide it at build time:
  ///   flutter build apk --dart-define=MAPBOX_PUBLIC_TOKEN=pk...
  static const String mapboxPublicToken = String.fromEnvironment(
    'MAPBOX_PUBLIC_TOKEN',
    defaultValue: '',
  );

  /// True when a Mapbox token has been provided at build time.
  static bool get hasMapboxToken => mapboxPublicToken.isNotEmpty;

  /// Supabase project URL (Supabase Auth — Google sign-in only; the app runs on
  /// our own JWTs once the backend has verified the Supabase token).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eqokkmvuxufhkjdsccyc.supabase.co',
  );

  /// Supabase anon / publishable key. Safe to ship in the client.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Ao6oEEFbGTqAjnAoQPTang_6i7N_CpM',
  );

  /// The Google **Web** OAuth client ID (the one configured in Supabase → Auth →
  /// Providers → Google). Native `google_sign_in` uses it as `serverClientId` so
  /// the returned idToken has the audience Supabase expects.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '929391543664-3sa7hb8b59gqq7vkq7ivk07tdbp4s2cr.apps.googleusercontent.com',
  );

  /// Agora RTC App ID (public — tokens are minted server-side per call).
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '44dc03816aee4e1bb9d17451eeb6d660',
  );

  /// Whether this is a release build.
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');

  /// Default city for the MVP.
  static const String defaultCity = 'Ranchi';
}
