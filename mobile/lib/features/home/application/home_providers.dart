import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:companion_ranchi/core/models/category_model.dart';
import 'package:companion_ranchi/core/models/companion_model.dart';
import 'package:companion_ranchi/features/home/data/home_repository.dart';
import 'package:companion_ranchi/features/home/presentation/location_picker.dart';

/// A best-effort device location used to bias "Popular Nearby". Resolves to a
/// [Position] when permission is granted, or `null` when unavailable/denied —
/// in which case the backend falls back to the default city. Never throws.
final deviceLocationProvider = FutureProvider<Position?>((ref) async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    // Prefer the instantly-available last-known fix so the "Near You" rail never
    // waits on a cold GPS lock. Only fall back to a fresh fix (short timeout) if
    // there's no cached position at all.
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) return lastKnown;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 3),
    );
  } catch (_) {
    return null;
  }
});

/// Activity categories shown as horizontal chips on the home screen.
final homeCategoriesProvider =
    FutureProvider.autoDispose<List<CategoryModel>>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  return repo.fetchCategories();
});

/// Featured companions for the home carousel. Re-fetches when the user changes
/// their home city so the list is filtered to that city.
final featuredCompanionsProvider =
    FutureProvider.autoDispose<List<CompanionModel>>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  final city = ref.watch(selectedLocationProvider)?.city;
  return repo.fetchFeatured(city: city);
});

/// Popular-nearby companions, biased by the device location when available and
/// filtered to the user's chosen home city.
final popularNearbyProvider =
    FutureProvider.autoDispose<List<CompanionModel>>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  final city = ref.watch(selectedLocationProvider)?.city;
  // Don't let the rail hang on a cold GPS lock: wait at most 1.5s for a fix,
  // then query city-only. The probe itself never throws.
  Position? position;
  try {
    position = await ref
        .watch(deviceLocationProvider.future)
        .timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    position = null; // timed out or unavailable — fall back to city
  }
  return repo.fetchPopularNearby(
    lat: position?.latitude,
    lng: position?.longitude,
    city: city,
  );
});
