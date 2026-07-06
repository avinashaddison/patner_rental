import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/features/calls/data/call_repository.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

/// Everything the call screen needs, passed via go_router `extra`.
class CallScreenArgs {
  const CallScreenArgs({
    required this.conversationId,
    required this.callId,
    required this.isCaller,
    required this.video,
    required this.peerName,
    this.peerPhotoUrl,
  });

  final String conversationId;
  final String callId;

  /// True when we started the call, false when answering an incoming ring.
  final bool isCaller;
  final bool video;
  final String peerName;
  final String? peerPhotoUrl;
}

enum _CallPhase {
  /// Callee: ringing, waiting for the user to accept/decline.
  incoming,

  /// Caller: invite sent, waiting for the peer to accept.
  dialing,

  /// Accepted — joining the media channel / waiting for remote media.
  connecting,

  /// Both sides publishing; timer running.
  active,

  /// Terminal — brief status flash before the screen pops.
  ended,
}

/// Full-screen voice/video call (Agora RTC).
///
/// One screen drives the whole lifecycle for both roles:
///  caller: dialing → connecting → active → ended
///  callee: incoming → connecting → active → ended
/// Signaling rides the app socket (call:invite/accept/reject/cancel/end);
/// media joins the `conv_<id>` Agora channel with a server-minted token.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.args});

  final CallScreenArgs args;

  /// Set while any call screen is mounted — used by the global incoming-call
  /// listener to auto-reject a second ring instead of stacking call UIs.
  static bool inCall = false;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late _CallPhase _phase;
  RtcEngine? _engine;
  int? _remoteUid;
  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  bool _frontCamera = true;
  bool _leaving = false;
  String _statusOverride = '';

  Timer? _ringTimeout;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _connectedAt;

  final _ringtone = FlutterRingtonePlayer();
  final List<StreamSubscription> _subs = [];

  CallScreenArgs get args => widget.args;
  SocketClient get _socket => ref.read(socketClientProvider);

  @override
  void initState() {
    super.initState();
    CallScreen.inCall = true;
    _phase = args.isCaller ? _CallPhase.dialing : _CallPhase.incoming;
    _speakerOn = args.video; // video → speaker, voice → earpiece
    _bindSignaling();
    if (args.isCaller) {
      _startOutgoing();
    } else {
      // Ring until the user decides or the caller gives up.
      _ringtone.playRingtone(looping: true);
      _ringTimeout = Timer(const Duration(seconds: 50), () {
        _finish('Missed call');
      });
    }
  }

  void _bindSignaling() {
    bool mine(dynamic e) => e.callId == args.callId;

    _subs.add(_socket.onCallAccepted.listen((e) {
      if (!mine(e) || !mounted) return;
      setState(() => _phase = _CallPhase.connecting);
      _ringTimeout?.cancel();
    }));
    _subs.add(_socket.onCallRejected.listen((e) {
      if (!mine(e)) return;
      _finish('Call declined');
    }));
    _subs.add(_socket.onCallCancelled.listen((e) {
      if (!mine(e)) return;
      _finish('Call cancelled');
    }));
    _subs.add(_socket.onCallEnded.listen((e) {
      if (!mine(e)) return;
      _finish('Call ended');
    }));
  }

  // ---- Lifecycle: outgoing ----

  Future<void> _startOutgoing() async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _finish('Microphone permission needed');
      return;
    }
    // Ring the peer first so their phone starts ringing while we join media.
    _socket.callInvite(
      callId: args.callId,
      conversationId: args.conversationId,
      video: args.video,
    );
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      _socket.callCancel(
        callId: args.callId,
        conversationId: args.conversationId,
      );
      _finish('No answer');
    });
    await _joinChannel();
  }

  // ---- Lifecycle: incoming ----

  Future<void> _accept() async {
    AppSounds.pop();
    _ringtone.stop();
    _ringTimeout?.cancel();
    final granted = await _ensurePermissions();
    if (!granted) {
      _socket.callReject(
        callId: args.callId,
        conversationId: args.conversationId,
      );
      _finish('Microphone permission needed');
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _CallPhase.connecting);
    _socket.callAccept(
      callId: args.callId,
      conversationId: args.conversationId,
    );
    await _joinChannel();
  }

  void _decline() {
    AppSounds.pop();
    _socket.callReject(
      callId: args.callId,
      conversationId: args.conversationId,
    );
    _finish('Call declined');
  }

  // ---- Media ----

  Future<bool> _ensurePermissions() async {
    final wanted = [
      Permission.microphone,
      if (args.video) Permission.camera,
    ];
    final results = await wanted.request();
    return results.values.every((s) => s.isGranted);
  }

  Future<void> _joinChannel() async {
    try {
      final creds =
          await ref.read(callRepositoryProvider).fetchToken(args.conversationId);

      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(RtcEngineContext(
        appId: creds.appId.isNotEmpty ? creds.appId : Env.agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      engine.registerEventHandler(RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          if (!mounted) return;
          setState(() {
            _remoteUid = remoteUid;
            _phase = _CallPhase.active;
          });
          _startTicker();
          AppSounds.success();
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (_remoteUid == remoteUid) _finish('Call ended');
        },
        onError: (err, msg) {
          debugPrint('Agora error: $err $msg');
        },
      ));

      if (args.video) {
        await engine.enableVideo();
        await engine.startPreview();
      }
      // Pre-join audio route (setEnableSpeakerphone is only legal IN channel
      // and throws before join). Route errors must never kill the call.
      try {
        await engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
      } catch (_) {}
      await engine.joinChannelWithUserAccount(
        token: creds.token,
        channelId: creds.channel,
        userAccount: creds.userAccount,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } catch (e) {
      debugPrint('Call join failed: $e');
      if (args.isCaller) {
        _socket.callCancel(
          callId: args.callId,
          conversationId: args.conversationId,
        );
      } else {
        _socket.callEnd(
          callId: args.callId,
          conversationId: args.conversationId,
        );
      }
      _finish('Could not connect the call');
    }
  }

  void _startTicker() {
    _connectedAt ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });
  }

  // ---- Controls ----

  void _toggleMute() {
    AppSounds.tick();
    setState(() => _muted = !_muted);
    _engine?.muteLocalAudioStream(_muted);
  }

  void _toggleSpeaker() {
    AppSounds.tick();
    setState(() => _speakerOn = !_speakerOn);
    _engine?.setEnableSpeakerphone(_speakerOn);
  }

  void _toggleCamera() {
    AppSounds.tick();
    setState(() => _cameraOff = !_cameraOff);
    _engine?.muteLocalVideoStream(_cameraOff);
    if (_cameraOff) {
      _engine?.stopPreview();
    } else {
      _engine?.startPreview();
    }
  }

  void _switchCamera() {
    AppSounds.tick();
    setState(() => _frontCamera = !_frontCamera);
    _engine?.switchCamera();
  }

  void _hangUp() {
    AppSounds.pop();
    if (_phase == _CallPhase.dialing) {
      _socket.callCancel(
        callId: args.callId,
        conversationId: args.conversationId,
      );
    } else {
      _socket.callEnd(
        callId: args.callId,
        conversationId: args.conversationId,
      );
    }
    _finish('Call ended');
  }

  /// Terminal transition: show [status] for a beat, then pop once.
  void _finish(String status) {
    if (_leaving) return;
    _leaving = true;
    _ringtone.stop();
    _ringTimeout?.cancel();
    _ticker?.cancel();
    if (mounted) {
      setState(() {
        _phase = _CallPhase.ended;
        _statusOverride = status;
      });
    }
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && context.canPop()) context.pop();
    });
  }

  @override
  void dispose() {
    CallScreen.inCall = false;
    _ringtone.stop();
    _ringTimeout?.cancel();
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      engine.leaveChannel();
      engine.release();
    }
    super.dispose();
  }

  // ---- UI ----

  String get _statusText {
    if (_statusOverride.isNotEmpty) return _statusOverride;
    switch (_phase) {
      case _CallPhase.incoming:
        return args.video ? 'Incoming video call…' : 'Incoming voice call…';
      case _CallPhase.dialing:
        return 'Ringing…';
      case _CallPhase.connecting:
        return 'Connecting…';
      case _CallPhase.active:
        return _formatDuration(_elapsed);
      case _CallPhase.ended:
        return 'Call ended';
    }
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo =
        args.video && _phase == _CallPhase.active && _remoteUid != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaving) _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF14101A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop: remote video when live, else a soft brand gradient.
            if (showRemoteVideo)
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection:
                      RtcConnection(channelId: 'conv_${args.conversationId}'),
                ),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2A1630), Color(0xFF14101A)],
                  ),
                ),
              ),

            // Local self-preview (video calls once our camera is running).
            if (args.video && _engine != null && !_cameraOff)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 110,
                    height: 160,
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                  ),
                ),
              ),

            // Identity block (hidden behind full-screen remote video).
            if (!showRemoteVideo)
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    UserAvatar(
                      photoUrl: args.peerPhotoUrl,
                      name: args.peerName,
                      radius: 56,
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        args.peerName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(flex: 3),
                  ],
                ),
              ),

            // In-call duration chip over remote video.
            if (showRemoteVideo)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        args.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom control deck.
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: _phase == _CallPhase.incoming
                      ? _IncomingControls(
                          video: args.video,
                          onAccept: _accept,
                          onDecline: _decline,
                        )
                      : _InCallControls(
                          video: args.video,
                          muted: _muted,
                          speakerOn: _speakerOn,
                          cameraOff: _cameraOff,
                          onMute: _toggleMute,
                          onSpeaker: _toggleSpeaker,
                          onCameraToggle: _toggleCamera,
                          onSwitchCamera: _switchCamera,
                          onHangUp: _hangUp,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accept / decline pair shown while an incoming call rings.
class _IncomingControls extends StatelessWidget {
  const _IncomingControls({
    required this.video,
    required this.onAccept,
    required this.onDecline,
  });

  final bool video;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundAction(
          icon: Icons.call_end_rounded,
          label: 'Decline',
          background: const Color(0xFFE53935),
          size: 68,
          onTap: onDecline,
        ),
        _RoundAction(
          icon: video ? Icons.videocam_rounded : Icons.call_rounded,
          label: 'Accept',
          background: const Color(0xFF2E7D32),
          size: 68,
          onTap: onAccept,
        ),
      ],
    );
  }
}

/// Mute / speaker / camera controls + the red hang-up button.
class _InCallControls extends StatelessWidget {
  const _InCallControls({
    required this.video,
    required this.muted,
    required this.speakerOn,
    required this.cameraOff,
    required this.onMute,
    required this.onSpeaker,
    required this.onCameraToggle,
    required this.onSwitchCamera,
    required this.onHangUp,
  });

  final bool video;
  final bool muted;
  final bool speakerOn;
  final bool cameraOff;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onCameraToggle;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundAction(
              icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: muted ? 'Unmute' : 'Mute',
              background: muted
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.18),
              iconColor: muted ? const Color(0xFF14101A) : Colors.white,
              onTap: onMute,
            ),
            if (video) ...[
              _RoundAction(
                icon: cameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                label: cameraOff ? 'Camera on' : 'Camera off',
                background: cameraOff
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18),
                iconColor: cameraOff ? const Color(0xFF14101A) : Colors.white,
                onTap: onCameraToggle,
              ),
              _RoundAction(
                icon: Icons.cameraswitch_rounded,
                label: 'Flip',
                background: Colors.white.withValues(alpha: 0.18),
                onTap: onSwitchCamera,
              ),
            ] else
              _RoundAction(
                icon: speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: 'Speaker',
                background: speakerOn
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18),
                iconColor: speakerOn ? const Color(0xFF14101A) : Colors.white,
                onTap: onSpeaker,
              ),
          ],
        ),
        const SizedBox(height: 24),
        _RoundAction(
          icon: Icons.call_end_rounded,
          label: 'End',
          background: AppColors.primary,
          size: 68,
          onTap: onHangUp,
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
    this.iconColor = Colors.white,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color iconColor;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: size * 0.45),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
