import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// hide Position — it clashes with Mapbox's geotypes Position; we only need
// Geolocator's static distance helper here.
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/tracking/application/live_tracking_controller.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Blinkit-style live tracking for an active booking. Both parties opt in to
/// share GPS; each sees the other move on the map in real time. The realtime
/// transport is the app's existing Socket.IO layer — Mapbox only draws it.
///
/// Degrades gracefully: with no Mapbox token the same live data renders as a
/// status card with an "Open in Maps" hand-off, so the feature is useful either
/// way.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({
    super.key,
    required this.bookingId,
    this.peerName,
  });

  final String bookingId;
  final String? peerName;

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  // Ranchi city centre — initial camera target before any fix arrives.
  static const double _ranchiLat = 23.3441;
  static const double _ranchiLng = 85.3096;

  MapboxMap? _map;
  PointAnnotationManager? _points;
  PolylineAnnotationManager? _lines;
  Uint8List? _meIcon;
  Uint8List? _peerIcon;
  bool _rendering = false;

  String get _peerLabel => widget.peerName ?? 'your meeting partner';

  @override
  Widget build(BuildContext context) {
    final provider = liveTrackingControllerProvider(widget.bookingId);

    // Re-draw markers + route + camera whenever either party's position changes.
    ref.listen(provider, (_, next) {
      final s = next.valueOrNull;
      if (s != null) _render(s);
    });

    final s = ref.watch(provider).valueOrNull ?? const LiveTrackingState();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Live location'),
        backgroundColor: AppColors.scaffold,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _mapOrFallback(s)),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: _ControlCard(
              state: s,
              peerLabel: _peerLabel,
              distanceLabel: _distanceLabel(s),
              etaLabel: _etaLabel(s),
              onToggleShare: () => _toggleShare(s),
              onOpenInMaps: s.peer != null
                  ? () => _openInMaps(s.peer!.lat, s.peer!.lng)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapOrFallback(LiveTrackingState s) {
    if (!Env.hasMapboxToken) {
      return _MapUnavailable(state: s, peerLabel: _peerLabel);
    }
    return MapWidget(
      key: const ValueKey('tracking-map'),
      styleUri: MapboxStyles.STANDARD,
      onMapCreated: _onMapCreated,
    );
  }

  // -- map lifecycle ---------------------------------------------------------

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    // Initial camera over Ranchi until the first fix arrives.
    await map.setCamera(CameraOptions(
      center: Point(coordinates: Position(_ranchiLng, _ranchiLat)),
      zoom: 12.0,
    ));
    // Keep the required Mapbox logo + attribution; drop the scale bar clutter.
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _points = await map.annotations.createPointAnnotationManager();
    _lines = await map.annotations.createPolylineAnnotationManager();
    _meIcon ??= await _circleMarkerBytes(const Color(0xFF2F80ED)); // blue = you
    _peerIcon ??= await _circleMarkerBytes(AppColors.primary); // pink = peer
    final s = ref.read(liveTrackingControllerProvider(widget.bookingId)).valueOrNull ??
        const LiveTrackingState();
    await _render(s);
  }

  /// Draw both markers + the route line, then fit the camera. Guarded so rapid
  /// socket updates don't overlap on the annotation managers.
  Future<void> _render(LiveTrackingState s) async {
    final pm = _points;
    final lm = _lines;
    if (pm == null || lm == null || _rendering) return;
    _rendering = true;
    try {
      await pm.deleteAll();
      final me = s.me;
      if (me != null && _meIcon != null) {
        await pm.create(PointAnnotationOptions(
          geometry: Point(coordinates: Position(me.lng, me.lat)),
          image: _meIcon,
          iconSize: 1.0,
        ));
      }
      final peer = s.peer;
      if (peer != null && _peerIcon != null) {
        await pm.create(PointAnnotationOptions(
          geometry: Point(coordinates: Position(peer.lng, peer.lat)),
          image: _peerIcon,
          iconSize: 1.0,
        ));
      }

      await lm.deleteAll();
      if (s.route.isNotEmpty) {
        await lm.create(PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: s.route.map((p) => Position(p.lng, p.lat)).toList(),
          ),
          lineColor: AppColors.primary.toARGB32(),
          lineWidth: 5.0,
        ));
      }

      await _updateCamera(s);
    } catch (_) {
      // Map not fully ready / transient annotation error — the next tick redraws.
    } finally {
      _rendering = false;
    }
  }

  Future<void> _updateCamera(LiveTrackingState s) async {
    final map = _map;
    if (map == null) return;
    final pts = <Position>[
      if (s.me != null) Position(s.me!.lng, s.me!.lat),
      if (s.peer != null) Position(s.peer!.lng, s.peer!.lat),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      await map.flyTo(
        CameraOptions(center: Point(coordinates: pts.first), zoom: 15.5),
        MapAnimationOptions(duration: 700),
      );
      return;
    }

    var minLng = pts.first.lng, maxLng = pts.first.lng;
    var minLat = pts.first.lat, maxLat = pts.first.lat;
    for (final p in pts) {
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
    }
    final camera = await map.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 90, left: 60, bottom: 240, right: 60),
      null,
      null,
      null,
      null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 700));
  }

  /// A soft-shadowed "dot" marker (white ring + coloured core) rendered to PNG
  /// bytes — Mapbox point annotations take an image, not a Flutter widget.
  Future<Uint8List> _circleMarkerBytes(Color color) async {
    const double size = 84;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const c = size / 2;
    canvas.drawCircle(
      Offset(c, c + 2),
      c * 0.60,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(Offset(c, c), c * 0.56, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(c, c), c * 0.42, Paint()..color = color);
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _toggleShare(LiveTrackingState s) async {
    final ctrl = ref.read(liveTrackingControllerProvider(widget.bookingId).notifier);
    if (s.sharing) {
      ctrl.stopSharing();
      return;
    }
    await ctrl.startSharing();
    final after = ref.read(liveTrackingControllerProvider(widget.bookingId)).valueOrNull;
    if (!mounted || after == null) return;
    if (after.serviceDisabled) {
      _snack('Turn on location services to share your live location.');
    } else if (after.permissionDenied) {
      _snack('Location permission is needed to share your location.');
    }
  }

  Future<void> _openInMaps(double lat, double lng) async {
    // Hand off to whichever maps app the user has (geo: scheme), else a web URL.
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (!await launchUrl(web, mode: LaunchMode.externalApplication)) {
      if (mounted) _snack('Could not open Maps.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _distanceLabel(LiveTrackingState s) {
    if (s.me == null || s.peer == null) return null;
    final m = Geolocator.distanceBetween(
      s.me!.lat,
      s.me!.lng,
      s.peer!.lat,
      s.peer!.lng,
    );
    if (m < 1000) return '${m.round()} m apart';
    return '${(m / 1000).toStringAsFixed(1)} km apart';
  }

  /// Road ETA from the Directions API, e.g. "~12 min away · 3.4 km by road".
  String? _etaLabel(LiveTrackingState s) {
    final secs = s.etaSeconds;
    if (secs == null) return null;
    final mins = (secs / 60).round();
    final meters = s.routeMeters;
    final dist = meters == null
        ? ''
        : meters < 1000
            ? ' · $meters m by road'
            : ' · ${(meters / 1000).toStringAsFixed(1)} km by road';
    return mins <= 1 ? 'Arriving now$dist' : '~$mins min away$dist';
  }
}

/// The floating control card: peer status, distance, share toggle, safety note.
class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.state,
    required this.peerLabel,
    required this.distanceLabel,
    required this.etaLabel,
    required this.onToggleShare,
    required this.onOpenInMaps,
  });

  final LiveTrackingState state;
  final String peerLabel;
  final String? distanceLabel;
  final String? etaLabel;
  final VoidCallback onToggleShare;
  final VoidCallback? onOpenInMaps;

  @override
  Widget build(BuildContext context) {
    final peerStatus = state.peerActive
        ? '${_capitalise(peerLabel)} is sharing live location'
        : 'Waiting for $peerLabel to share…';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(active: state.peerActive),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  peerStatus,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (distanceLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.field,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    distanceLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (etaLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.directions_car_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  etaLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          GradientButton(
            label: state.sharing
                ? 'Stop sharing my location'
                : 'Share my live location',
            icon: state.sharing
                ? Icons.location_off_rounded
                : Icons.my_location_rounded,
            gradient: state.sharing
                ? const LinearGradient(
                    colors: [AppColors.inkMuted, AppColors.inkMuted],
                  )
                : null,
            onPressed: onToggleShare,
          ),
          if (onOpenInMaps != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onOpenInMaps,
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: Text('Get directions to $peerLabel'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const SafetyBanner(
            message:
                'Live location is shared only during this booking, and only '
                'while you choose to share it. Meet in public places.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.inkMuted;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: active
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
      ),
    );
  }
}

/// Shown when no Mapbox token is configured: the live data is still useful as a
/// status card with an "Open in Maps" hand-off.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.state, required this.peerLabel});

  final LiveTrackingState state;
  final String peerLabel;

  @override
  Widget build(BuildContext context) {
    final peer = state.peer;
    return Container(
      color: AppColors.field,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, size: 56, color: AppColors.inkMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            peer == null
                ? 'Waiting for a live location…'
                : '$peerLabel is at\n${peer.lat.toStringAsFixed(5)}, ${peer.lng.toStringAsFixed(5)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Map view needs a Mapbox token.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
