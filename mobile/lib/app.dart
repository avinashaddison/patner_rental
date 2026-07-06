import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';
import 'package:companion_ranchi/core/router/app_router.dart';
import 'package:companion_ranchi/core/router/routes.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/theme/theme_provider.dart';
import 'package:companion_ranchi/features/calls/presentation/call_screen.dart';

/// Root application widget. Wires the go_router, light/dark themes and the
/// persisted theme mode together via [MaterialApp.router].
///
/// Also owns the app-lifecycle → socket bridge: the realtime socket is
/// disconnected while the app is backgrounded and reconnected on resume.
/// This makes the server's "is this user online?" check accurate, so chat
/// messages that arrive while the app isn't in the foreground correctly fall
/// through to an FCM push (instead of being swallowed by a background socket
/// that keeps the user looking "online").
class CompanionRanchiApp extends ConsumerStatefulWidget {
  const CompanionRanchiApp({super.key});

  @override
  ConsumerState<CompanionRanchiApp> createState() => _CompanionRanchiAppState();
}

class _CompanionRanchiAppState extends ConsumerState<CompanionRanchiApp>
    with WidgetsBindingObserver {
  StreamSubscription<IncomingCallEvent>? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Global ring handler: any `call:incoming` opens the full-screen call UI,
    // wherever the user currently is in the app.
    final socket = ref.read(socketClientProvider);
    _incomingCallSub = socket.onIncomingCall.listen((event) {
      if (event.callId.isEmpty || event.conversationId.isEmpty) return;
      if (CallScreen.inCall) {
        // Already on a call — tell the second caller we're busy.
        socket.callReject(
          callId: event.callId,
          conversationId: event.conversationId,
        );
        return;
      }
      ref.read(goRouterProvider).push(
            Routes.call,
            extra: CallScreenArgs(
              conversationId: event.conversationId,
              callId: event.callId,
              isCaller: false,
              video: event.video,
              peerName: event.fromName,
              peerPhotoUrl: event.fromPhotoUrl,
            ),
          );
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final socket = ref.read(socketClientProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        // Back in the foreground → reconnect for live badges/sound. The
        // conversations controller silent-refreshes on reconnect, catching up
        // on anything that landed via push while we were away.
        socket.connect();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Backgrounded → drop the socket so the server marks us offline and
        // pushes new messages instead. EXCEPT during an active call: the
        // mic/camera permission dialog (and the call itself) briefly pauses
        // the activity, and dropping the socket there would lose the
        // call:accept/end signaling mid-call.
        if (!CallScreen.inCall) socket.disconnect();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        // Lock text scaling to a sane range so the premium layout holds.
        final media = MediaQuery.of(context);
        final clamped = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
