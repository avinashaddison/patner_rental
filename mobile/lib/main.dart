import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:companion_ranchi/app.dart';
import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/features/home/presentation/location_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mapbox access token for the live-tracking map. Injected at build time via
  // --dart-define=MAPBOX_PUBLIC_TOKEN; when absent the map degrades gracefully.
  if (Env.mapboxPublicToken.isNotEmpty) {
    MapboxOptions.setAccessToken(Env.mapboxPublicToken);
  }

  // Allow all orientations on tablets but keep phones portrait for the
  // marketplace layout.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Supabase Auth — used only for Google sign-in. We obtain a verified identity
  // token from Supabase; the backend then verifies it and issues our own app JWTs.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // supabase_flutter 2.15+ renamed anonKey → publishableKey (same value).
    publishableKey: Env.supabaseAnonKey,
  );

  // Initialise Firebase (Phone Auth, messaging). On Android the config comes
  // from android/app/google-services.json via the google-services Gradle
  // plugin, so no options are needed here. Guarded so the app still runs (with
  // the backend-OTP fallback) if Firebase isn't configured for a build.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured for this build — phone auth falls back to the
    // backend OTP flow; the rest of the app is unaffected.
  }

  // Load persisted prefs (remembers the chosen home location across restarts).
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CompanionRanchiApp(),
    ),
  );
}
