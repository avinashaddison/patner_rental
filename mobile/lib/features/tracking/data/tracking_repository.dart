import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/features/tracking/data/polyline_codec.dart';

/// A decoded route between two points: the polyline geometry plus the road
/// distance and travel-time ETA. Any field may be null if Maps isn't configured
/// server-side (the proxy returns no route and the map simply omits the line).
class RoutePreview {
  const RoutePreview({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
  });

  /// `[lat, lng]` pairs along the route.
  final List<List<double>> points;
  final int? distanceMeters;
  final int? durationSeconds;
}

/// A place-autocomplete suggestion (`primary` = name, `secondary` = area).
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primary,
    required this.secondary,
  });
  final String placeId;
  final String primary;
  final String secondary;

  String get label => secondary.isEmpty ? primary : '$primary, $secondary';
}

/// A resolved place with coordinates.
class PlaceDetail {
  const PlaceDetail({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });
  final String name;
  final String address;
  final double lat;
  final double lng;
}

/// Talks to the backend Routes/Places/Geocoding proxies under `/tracking`. The
/// Google server key lives only on the backend, so the client never holds it.
class TrackingRepository {
  TrackingRepository(this._api);

  final ApiClient _api;

  /// `GET /tracking/places/autocomplete` — Ranchi-biased place search. Returns
  /// [] when Maps isn't configured server-side. Pass a stable [sessionToken]
  /// per search session (regenerate after a selection) for cheap billing.
  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    String? sessionToken,
  }) async {
    final data = await _api.getJson(
      '/tracking/places/autocomplete',
      query: {
        'q': query,
        if (sessionToken != null) 'session': sessionToken,
      },
    );
    if (data is! Map) return const [];
    final list = data['suggestions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map(
          (m) => PlaceSuggestion(
            placeId: m['placeId']?.toString() ?? '',
            primary: m['primary']?.toString() ?? '',
            secondary: m['secondary']?.toString() ?? '',
          ),
        )
        .where((s) => s.placeId.isNotEmpty && s.primary.isNotEmpty)
        .toList(growable: false);
  }

  /// `GET /tracking/places/details` — resolve a placeId to coordinates.
  Future<PlaceDetail?> placeDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    final data = await _api.getJson(
      '/tracking/places/details',
      query: {
        'placeId': placeId,
        if (sessionToken != null) 'session': sessionToken,
      },
    );
    if (data is! Map) return null;
    final p = data['place'];
    if (p is! Map) return null;
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return PlaceDetail(
      name: p['name']?.toString() ?? '',
      address: p['address']?.toString() ?? '',
      lat: lat,
      lng: lng,
    );
  }

  /// `GET /tracking/geocode/reverse` — coordinates to a human address (or null).
  Future<String?> reverseGeocode(double lat, double lng) async {
    final data = await _api.getJson(
      '/tracking/geocode/reverse',
      query: {'lat': lat.toString(), 'lng': lng.toString()},
    );
    if (data is! Map) return null;
    final addr = data['address'];
    return addr is String && addr.isNotEmpty ? addr : null;
  }

  /// `PATCH /companion/location` — save the calling companion's base
  /// coordinates (powers "near me" / distance). Companion role only.
  Future<void> updateCompanionLocation(double lat, double lng) async {
    await _api.patchJson(
      '/companion/location',
      body: {'latitude': lat, 'longitude': lng},
    );
  }

  /// Fetch a route + ETA from [origin] to [destination] for a booking. Returns
  /// null when no route is available (Maps unconfigured / Google produced none).
  Future<RoutePreview?> fetchRoute({
    required String bookingId,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String mode = 'DRIVE',
  }) async {
    final data = await _api.postJson(
      '/tracking/route',
      body: {
        'bookingId': bookingId,
        'origin': {'lat': originLat, 'lng': originLng},
        'destination': {'lat': destLat, 'lng': destLng},
        'mode': mode,
      },
    );
    if (data is! Map) return null;
    final route = data['route'];
    if (route is! Map) return null;

    final encoded = route['encodedPolyline']?.toString();
    final points = (encoded != null && encoded.isNotEmpty)
        ? decodePolyline(encoded)
        : <List<double>>[];

    return RoutePreview(
      points: points,
      distanceMeters: (route['distanceMeters'] as num?)?.toInt(),
      durationSeconds: (route['durationSeconds'] as num?)?.toInt(),
    );
  }
}

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
  return TrackingRepository(ref.watch(apiClientProvider));
});
