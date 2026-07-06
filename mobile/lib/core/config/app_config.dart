import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_client.dart';

/// Public runtime config fetched from `GET /meta/config`.
///
/// Only the fields the app actually consumes are modelled here. The endpoint is
/// public (no auth), so this is safe to read on the login screen before sign-in.
class AppConfig {
  const AppConfig({
    this.loginHeroImageUrl,
    this.onboardingImageUrls = const [null, null, null],
    this.homeBannerImageUrls = const [null, null, null],
    this.onlinePaymentEnabled = true,
    this.cashPaymentEnabled = false,
    this.categoryIconScale = 0.46,
    this.cities = const ['Ranchi'],
  });

  /// Admin-set hero photo for the login screen. `null` when unset — callers
  /// should fall back to the bundled asset.
  final String? loginHeroImageUrl;

  /// Admin-set photos for the 3 onboarding steps (always length 3; each entry
  /// is `null` when unset, so callers fall back to the bundled asset).
  final List<String?> onboardingImageUrls;

  /// Admin-set promo images for the home carousel (always length 3; `null`
  /// entries mean "use the default designed card for that slide").
  final List<String?> homeBannerImageUrls;

  /// The non-null home banner URLs, in order — the actual slides to show.
  List<String> get homeBanners =>
      homeBannerImageUrls.whereType<String>().toList(growable: false);

  /// Admin-toggled payment methods. Online (Razorpay) defaults on; cash defaults
  /// off unless the server says otherwise.
  final bool onlinePaymentEnabled;
  final bool cashPaymentEnabled;

  /// Admin-controlled home category icon size, as a 0..1 fraction of the tile
  /// the icon fills. Clamped to a sane range; defaults to 0.46.
  final double categoryIconScale;

  /// Cities the marketplace operates in (admin-controlled). Used by the home
  /// location picker. Always non-empty.
  final List<String> cities;

  static String? _clean(dynamic v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final onboarding = <String?>[null, null, null];
    final raw = json['onboardingImageUrls'];
    if (raw is List) {
      for (var i = 0; i < 3 && i < raw.length; i++) {
        onboarding[i] = _clean(raw[i]);
      }
    }
    final banners = <String?>[null, null, null];
    final rawBanners = json['homeBannerImageUrls'];
    if (rawBanners is List) {
      for (var i = 0; i < 3 && i < rawBanners.length; i++) {
        banners[i] = _clean(rawBanners[i]);
      }
    }
    final pm = json['paymentMethods'];
    // "Online" covers any online rail: UPI QR (direct), UPI page, or Razorpay.
    // Each is enabled unless explicitly set false.
    final online = pm is Map
        ? (pm['upiqr'] != false ||
            pm['upigateway'] != false ||
            pm['razorpay'] != false)
        : true;
    final cash = pm is Map ? pm['cash'] == true : false;

    final rawScale = json['categoryIconScale'];
    final scale = rawScale is num ? rawScale.toDouble() : 0.46;

    final rawCities = json['cities'];
    final cities = rawCities is List
        ? rawCities
            .map((c) => c is String ? c.trim() : '')
            .where((c) => c.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return AppConfig(
      loginHeroImageUrl: _clean(json['loginHeroImageUrl']),
      onboardingImageUrls: onboarding,
      homeBannerImageUrls: banners,
      onlinePaymentEnabled: online,
      cashPaymentEnabled: cash,
      categoryIconScale: scale.clamp(0.3, 1.0),
      cities: cities.isEmpty ? const ['Ranchi'] : cities,
    );
  }

  static const AppConfig empty = AppConfig();
}

/// Fetches public app config. `autoDispose` so it re-fetches each time a screen
/// that watches it mounts (e.g. the login screen), picking up admin changes.
///
/// Never throws: any network/parse failure resolves to [AppConfig.empty] so the
/// UI degrades gracefully to bundled assets instead of erroring.
final appConfigProvider = FutureProvider.autoDispose<AppConfig>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final data = await api.getJson('/meta/config', skipAuth: true);
    if (data is Map) {
      return AppConfig.fromJson(Map<String, dynamic>.from(data));
    }
    return AppConfig.empty;
  } catch (_) {
    return AppConfig.empty;
  }
});
