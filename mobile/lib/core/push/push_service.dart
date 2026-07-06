import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/router/app_router.dart';
import 'package:companion_ranchi/core/router/routes.dart';

/// FCM notification channel carrying our custom tray sound. Must match the
/// `channelId` the backend sets on each push, and its sound file must live at
/// android/app/src/main/res/raw/companion_notify.wav. Channels are immutable
/// once created — bump this id (e.g. _v2) if the sound/importance ever changes.
const String kAlertsChannelId = 'companion_alerts_v1';

/// Firebase Cloud Messaging wiring for the authenticated session.
///
/// The backend already pushes on every `notify()` (bookings, chat-when-
/// offline, KYC, SOS…) via `sendPushToUser`; this service is the missing
/// mobile half:
///  1. request the Android 13+ notification permission,
///  2. register the device token with `POST /auth/fcm-token` (+ re-register
///     on token rotation),
///  3. route notification taps to the right screen from the data payload
///     (conversationId → chat thread, bookingId → booking detail,
///     anything else → the notifications list).
///
/// Foreground pushes are intentionally NOT shown as system notifications —
/// the in-app socket layer already covers that with live badges + sound.
/// Safe no-op when Firebase isn't configured for the build (no
/// google-services.json): [start] just returns.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openSub;
  bool _started = false;

  /// Idempotent — call freely from widgets that exist only while logged in.
  Future<void> start() async {
    if (_started || Firebase.apps.isEmpty) return;
    _started = true;

    await _ensureChannel();

    final fm = FirebaseMessaging.instance;
    try {
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token != null && token.isNotEmpty) {
        await _ref
            .read(authControllerProvider.notifier)
            .registerFcmToken(token);
      }
    } catch (_) {
      // Push is best-effort; never let it break the session.
    }

    _tokenSub = fm.onTokenRefresh.listen((t) {
      _ref.read(authControllerProvider.notifier).registerFcmToken(t);
    });

    // App in background → user taps the notification.
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_routeFor);
    // App was terminated → launched from a notification tap.
    final initial = await fm.getInitialMessage();
    if (initial != null) _routeFor(initial);
  }

  /// Register the high-importance notification channel that carries the custom
  /// tray sound, so background/terminated pushes (rendered by the system, not
  /// Dart) play companion_notify.wav. No-op off Android.
  Future<void> _ensureChannel() async {
    if (!Platform.isAndroid) return;
    const channel = AndroidNotificationChannel(
      kAlertsChannelId,
      'Companion alerts',
      description: 'Bookings, messages and updates',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('companion_notify'),
      playSound: true,
    );
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (_) {
      // Non-fatal — falls back to the default channel/sound.
    }
  }

  void _routeFor(RemoteMessage message) {
    final data = message.data;
    final router = _ref.read(goRouterProvider);
    final conversationId = data['conversationId']?.toString() ?? '';
    final bookingId = data['bookingId']?.toString() ?? '';
    if (conversationId.isNotEmpty) {
      router.push(Routes.chatThreadPath(conversationId));
    } else if (bookingId.isNotEmpty) {
      router.push(Routes.bookingDetailPath(bookingId));
    } else {
      router.push(Routes.notifications);
    }
  }

  void dispose() {
    _tokenSub?.cancel();
    _openSub?.cancel();
  }
}

/// Session-wide push service. Widgets that only exist while authenticated
/// (e.g. the main nav shell) call `ref.read(pushServiceProvider).start()`.
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});
