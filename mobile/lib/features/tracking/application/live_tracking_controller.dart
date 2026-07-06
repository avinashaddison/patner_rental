import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/features/tracking/data/tracking_repository.dart';

/// A single geo point with optional heading + freshness timestamp.
@immutable
class TrackPoint {
  const TrackPoint(this.lat, this.lng, {this.heading, this.at});
  final double lat;
  final double lng;
  final double? heading;
  final DateTime? at;
}

/// View-state for the live-tracking map of one booking.
///
/// [me] is this device's last GPS fix (only populated while [sharing]); [peer]
/// is the other party's last received fix. [peerActive] reflects whether the
/// peer is currently sharing. The map renders whichever points are non-null.
@immutable
class LiveTrackingState {
  const LiveTrackingState({
    this.me,
    this.peer,
    this.peerActive = false,
    this.sharing = false,
    this.permissionDenied = false,
    this.serviceDisabled = false,
    this.route = const [],
    this.etaSeconds,
    this.routeMeters,
  });

  final TrackPoint? me;
  final TrackPoint? peer;
  final bool peerActive;
  final bool sharing;
  final bool permissionDenied;
  final bool serviceDisabled;

  /// Road route geometry from [me] to [peer] (empty until a route is fetched).
  final List<TrackPoint> route;

  /// Travel-time ETA + road distance between the two parties (null until known).
  final int? etaSeconds;
  final int? routeMeters;

  LiveTrackingState copyWith({
    TrackPoint? me,
    TrackPoint? peer,
    bool? peerActive,
    bool? sharing,
    bool? permissionDenied,
    bool? serviceDisabled,
    List<TrackPoint>? route,
    int? etaSeconds,
    int? routeMeters,
  }) {
    return LiveTrackingState(
      me: me ?? this.me,
      peer: peer ?? this.peer,
      peerActive: peerActive ?? this.peerActive,
      sharing: sharing ?? this.sharing,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      serviceDisabled: serviceDisabled ?? this.serviceDisabled,
      route: route ?? this.route,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      routeMeters: routeMeters ?? this.routeMeters,
    );
  }
}

/// Drives booking-scoped, opt-in live location sharing for one booking.
///
/// On open it connects the socket and subscribes to the peer's pings, but does
/// NOT start sharing the user's own location until [startSharing] is called
/// (explicit consent). While sharing it streams GPS fixes (distance-filtered)
/// to the backend, which relays them only to the booking peer. Everything is
/// torn down on dispose so tracking can never outlive the screen.
class LiveTrackingController
    extends AutoDisposeFamilyAsyncNotifier<LiveTrackingState, String> {
  SocketClient get _socket => ref.read(socketClientProvider);
  TrackingRepository get _routes => ref.read(trackingRepositoryProvider);

  late final String _bookingId;
  late final String _myUserId;
  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<Position>? _gpsSub;

  // Route refresh throttling: recompute the road route + ETA at most once per
  // [_routeMinInterval] to keep Routes-API usage tiny (marker movement between
  // refreshes is free animation).
  static const Duration _routeMinInterval = Duration(seconds: 30);
  DateTime? _lastRouteAt;
  bool _routeInFlight = false;
  bool _disposed = false;

  @override
  Future<LiveTrackingState> build(String arg) async {
    _bookingId = arg;
    _myUserId = ref.read(currentUserProvider)?.id ?? '';

    unawaited(_socket.connect());

    _subs
      ..add(_socket.onLocationUpdate.listen(_onPeerUpdate))
      ..add(_socket.onLocationPeer.listen(_onPeerToggle));

    ref.onDispose(() {
      _disposed = true;
      _gpsSub?.cancel();
      // Best-effort: tell the peer we stopped if we were sharing.
      _socket.stopLocation(_bookingId);
      for (final s in _subs) {
        s.cancel();
      }
    });

    return const LiveTrackingState();
  }

  LiveTrackingState get _state =>
      state.valueOrNull ?? const LiveTrackingState();

  // -- sharing (this device) -------------------------------------------------

  /// Begin sharing this device's location with the booking peer. Requests
  /// location permission first; a denial surfaces in state without throwing.
  Future<void> startSharing() async {
    if (_state.sharing) return;
    final ok = await _ensurePermission();
    if (!ok) return;

    _socket.joinLocation(_bookingId);
    state = AsyncData(_state.copyWith(sharing: true));

    // Seed an immediate fix so the peer (and our own marker) appear at once,
    // then stream distance-filtered updates.
    unawaited(_pushOneFix());
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8, // metres moved before a new fix is emitted
      ),
    ).listen(_onMyPosition, onError: (_) {});
  }

  /// Stop sharing. The peer is notified and our GPS stream is released.
  void stopSharing() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _socket.stopLocation(_bookingId);
    state = AsyncData(_state.copyWith(sharing: false));
  }

  Future<void> _pushOneFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
      _onMyPosition(p);
    } catch (_) {
      // Stream will deliver the first fix shortly; non-fatal.
    }
  }

  void _onMyPosition(Position p) {
    if (!_state.sharing) return;
    state = AsyncData(
      _state.copyWith(
        me: TrackPoint(
          p.latitude,
          p.longitude,
          heading: p.heading,
          at: DateTime.now(),
        ),
      ),
    );
    _socket.sendLocation(
      bookingId: _bookingId,
      lat: p.latitude,
      lng: p.longitude,
      heading: p.heading,
      speed: p.speed,
      accuracy: p.accuracy,
    );
    unawaited(_maybeRefreshRoute());
  }

  // -- incoming peer events --------------------------------------------------

  void _onPeerUpdate(LocationUpdateEvent e) {
    if (e.bookingId != _bookingId || e.userId == _myUserId) return;
    state = AsyncData(
      _state.copyWith(
        peer: TrackPoint(e.lat, e.lng, heading: e.heading, at: e.at),
        peerActive: true,
      ),
    );
    unawaited(_maybeRefreshRoute());
  }

  void _onPeerToggle(LocationPeerEvent e) {
    if (e.bookingId != _bookingId || e.userId == _myUserId) return;
    state = AsyncData(_state.copyWith(peerActive: e.active));
  }

  // -- route + ETA (throttled) -----------------------------------------------

  /// Recompute the road route + ETA from me → peer, at most once per
  /// [_routeMinInterval]. No-op until both positions are known. Failures are
  /// swallowed so the markers keep updating even without a route line.
  Future<void> _maybeRefreshRoute() async {
    final s = _state;
    if (s.me == null || s.peer == null) return;
    if (_routeInFlight) return;
    final now = DateTime.now();
    if (_lastRouteAt != null &&
        now.difference(_lastRouteAt!) < _routeMinInterval) {
      return;
    }
    _lastRouteAt = now;
    _routeInFlight = true;
    try {
      final preview = await _routes.fetchRoute(
        bookingId: _bookingId,
        originLat: s.me!.lat,
        originLng: s.me!.lng,
        destLat: s.peer!.lat,
        destLng: s.peer!.lng,
      );
      if (_disposed || preview == null) return;
      state = AsyncData(
        _state.copyWith(
          route: preview.points
              .map((p) => TrackPoint(p[0], p[1]))
              .toList(growable: false),
          etaSeconds: preview.durationSeconds,
          routeMeters: preview.distanceMeters,
        ),
      );
    } catch (_) {
      // Non-fatal: keep the live markers, just no route line this round.
    } finally {
      _routeInFlight = false;
    }
  }

  // -- permission ------------------------------------------------------------

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = AsyncData(_state.copyWith(serviceDisabled: true));
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        state = AsyncData(_state.copyWith(permissionDenied: true));
        return false;
      }
      state = AsyncData(
        _state.copyWith(permissionDenied: false, serviceDisabled: false),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Live-tracking controller keyed by bookingId.
final liveTrackingControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    LiveTrackingController, LiveTrackingState, String>(
  LiveTrackingController.new,
);
