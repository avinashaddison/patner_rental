import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:companion_ranchi/core/config/app_config.dart';
import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';

/// The user's chosen home location. [label] is the display string shown in the
/// header; [city] (when known) is the city used to filter companion lists.
class SelectedLocation {
  const SelectedLocation({required this.label, this.city});
  final String label;
  final String? city;
}

const _kLabelKey = 'home_location_label';
const _kCityKey = 'home_location_city';

/// Curated popular Indian cities shown as quick picks (anything else is found
/// via search). Ranchi (the launch city) is kept near the top.
const List<String> _popularIndianCities = [
  'Ranchi',
  'Mumbai',
  'Delhi',
  'Bengaluru',
  'Hyderabad',
  'Chennai',
  'Kolkata',
  'Pune',
  'Ahmedabad',
  'Jaipur',
  'Lucknow',
  'Patna',
  'Bhubaneswar',
  'Chandigarh',
];

/// Injected in `main()` after loading prefs — see [SharedPreferences].
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// The chosen location, restored from disk on launch (persists across restarts).
/// `null` → the header falls back to the default city label and lists aren't
/// city-filtered.
final selectedLocationProvider = StateProvider<SelectedLocation?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final label = prefs.getString(_kLabelKey);
  if (label == null || label.isEmpty) return null;
  return SelectedLocation(label: label, city: prefs.getString(_kCityKey));
});

/// Sets the location in state and persists it to disk.
void applySelectedLocation(WidgetRef ref, SelectedLocation loc) {
  ref.read(selectedLocationProvider.notifier).state = loc;
  final prefs = ref.read(sharedPreferencesProvider);
  prefs.setString(_kLabelKey, loc.label);
  if (loc.city != null && loc.city!.isNotEmpty) {
    prefs.setString(_kCityKey, loc.city!);
  } else {
    prefs.remove(_kCityKey);
  }
}

/// Opens the "Set your location" bottom sheet.
Future<void> showLocationPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LocationPickerSheet(),
  );
}

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet();

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _locating = false;
  bool _searching = false;
  List<SelectedLocation> _results = const [];
  int _searchSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---- current location ----------------------------------------------------

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _msg('Turn on location services to detect your location.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _msg('Location permission is needed to detect your location.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final loc = await _reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (loc != null) {
        applySelectedLocation(ref, loc);
        Navigator.pop(context);
      } else {
        _msg('Couldn\'t read your area. Please search for a city instead.');
      }
    } catch (_) {
      _msg('Couldn\'t detect your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Coordinates → "Area, Region" + city-level name (used to filter companions).
  Future<SelectedLocation?> _reverseGeocode(double lat, double lng) async {
    const token = Env.mapboxPublicToken;
    if (token.isEmpty) return null;
    try {
      final res = await Dio().get(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json',
        queryParameters: {
          'types': 'place,locality,neighborhood,region',
          'limit': 1,
          'access_token': token,
        },
      );
      final features = (res.data?['features'] as List?) ?? const [];
      if (features.isEmpty) return null;
      return _hitFromFeature(features.first as Map);
    } catch (_) {
      return null;
    }
  }

  // ---- search --------------------------------------------------------------

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    final hits = await _forwardGeocode(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  /// Forward-geocode a query to Indian cities/towns.
  Future<List<SelectedLocation>> _forwardGeocode(String q) async {
    const token = Env.mapboxPublicToken;
    if (token.isEmpty) return const [];
    try {
      final res = await Dio().get(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json',
        queryParameters: {
          'country': 'in',
          'types': 'place,locality,district',
          'language': 'en',
          'limit': 6,
          'access_token': token,
        },
      );
      final features = (res.data?['features'] as List?) ?? const [];
      return features
          .map((f) => _hitFromFeature(f as Map))
          .whereType<SelectedLocation>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Builds a [SelectedLocation] from a Mapbox feature: label = "City, Region",
  /// city = the place-level name.
  SelectedLocation? _hitFromFeature(Map f) {
    final text = f['text'] as String?;
    final placeTypes =
        (f['place_type'] as List?)?.map((e) => '$e').toList() ?? const [];
    String? region;
    String? city;
    if (placeTypes.contains('place')) city = text;
    final ctx = f['context'] as List?;
    if (ctx != null) {
      for (final c in ctx) {
        final id = (c as Map)['id'] as String? ?? '';
        if (id.startsWith('region')) region = c['text'] as String?;
        if (id.startsWith('place') && city == null) {
          city = c['text'] as String?;
        }
      }
    }
    final display =
        (text != null && text.isNotEmpty) ? text : f['place_name'] as String?;
    if (display == null || display.isEmpty) return null;
    final label = (region != null && region.isNotEmpty && !display.contains(region))
        ? '$display, $region'
        : display;
    return SelectedLocation(label: label, city: city ?? text);
  }

  void _select(SelectedLocation loc) {
    applySelectedLocation(ref, loc);
    Navigator.pop(context);
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = ref.watch(selectedLocationProvider)?.city;
    // Popular cities = admin's service cities merged with the curated list.
    final configCities =
        ref.watch(appConfigProvider).valueOrNull?.cities ?? const ['Ranchi'];
    final popular = <String>[
      ...configCities,
      ..._popularIndianCities.where((c) => !configCities.contains(c)),
    ];
    final hasQuery = _searchCtrl.text.trim().length >= 2;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusLg)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              const Text(
                'Set your location',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Search any city in India, or detect it automatically.',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              // Search field.
              TextField(
                controller: _searchCtrl,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search city or town…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onQueryChanged('');
                            setState(() {});
                          },
                        ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: hasQuery
                    ? _buildResults()
                    : _buildDefault(popular, selectedCity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No matching places. Try another spelling.',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (_, i) => _ResultTile(
        icon: Icons.location_on_rounded,
        title: _results[i].label,
        onTap: () => _select(_results[i]),
      ),
    );
  }

  Widget _buildDefault(List<String> popular, String? selectedCity) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionTile(
            icon: Icons.my_location_rounded,
            title: 'Use my current location',
            subtitle: 'Detect your area via GPS',
            busy: _locating,
            onTap: _locating ? null : _useCurrentLocation,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'POPULAR CITIES',
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: AppColors.line)),
            ],
          ),
          const SizedBox(height: 4),
          ...popular.map(
            (c) => _ResultTile(
              icon: Icons.location_city_rounded,
              title: c,
              selected: c == selectedCity,
              onTap: () => _select(SelectedLocation(label: c, city: c)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.field,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                      ),
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

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.inkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
