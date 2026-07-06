import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// App sound effects.
///
/// Two kinds of audio, used deliberately:
///  * [notification] — the SYSTEM notification tone, for realtime alerts
///    (new message / notification badges). Debounced to one per 1.2s.
///  * Short bundled SFX ([pop], [whoosh], [tick], [success], [error],
///    [sosAlert]) for reward/confirmation moments, most paired with a light
///    haptic. Generated in-house (assets/sounds/*.wav) — no licensing risk.
///
/// Ordinary buttons/navigation intentionally get NO sound (haptics at most):
/// sounding every tap makes an app feel like a toy and users mute it.
class AppSounds {
  AppSounds._();

  static final FlutterRingtonePlayer _ringtone = FlutterRingtonePlayer();
  static DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);

  // A single low-latency player for short SFX; a new play() call simply
  // replaces the previous clip, which is the behaviour we want for rapid taps.
  static final AudioPlayer _sfx = AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop);

  static void _play(String asset, {double volume = 1.0}) {
    // Fire-and-forget; sound failures must never break app flow.
    _sfx.play(AssetSource('sounds/$asset'), volume: volume).catchError((_) {});
  }

  /// System notification tone (realtime badge alerts). Rate-limited so bursts
  /// of messages don't machine-gun the speaker.
  static void notification() {
    final now = DateTime.now();
    if (now.difference(_lastNotification) <
        const Duration(milliseconds: 1200)) {
      return;
    }
    _lastNotification = now;
    try {
      _ringtone.playNotification();
    } catch (_) {
      // ignore — some OEM ROMs restrict background stream access.
    }
  }

  /// Bubbly "pop" — swipe-right like on the swap deck, wishlist hearts.
  static void pop() {
    HapticFeedback.lightImpact();
    _play('pop.wav', volume: 1.0);
  }

  /// Soft "whoosh" — swipe-left skip, message sent.
  static void whoosh() {
    HapticFeedback.selectionClick();
    _play('whoosh.wav', volume: 0.7);
  }

  /// Tiny "tick" — small confirmations (copy, toggle).
  static void tick() {
    HapticFeedback.selectionClick();
    _play('tick.wav', volume: 0.6);
  }

  /// Rising chime — payment confirmed, meeting started, submissions.
  static void success() {
    HapticFeedback.mediumImpact();
    _play('success.wav');
  }

  /// Low descending tone — payment failed and other hard errors.
  static void error() {
    HapticFeedback.heavyImpact();
    _play('error.wav', volume: 0.9);
  }

  /// Loud urgent siren for SOS — intentionally NOT debounced or quiet.
  static void sosAlert() {
    HapticFeedback.heavyImpact();
    _play('sos.wav');
  }
}
