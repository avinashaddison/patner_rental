import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:companion_ranchi/features/settings/data/settings_repository.dart';

/// Shared secure storage handle for locally-persisted settings (notification
/// toggles, language). Theme is handled separately by `themeModeProvider`.
final _settingsStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

/// Blocked users list (`GET /users/blocks`).
final blockedUsersProvider =
    FutureProvider.autoDispose<List<BlockedUser>>((ref) async {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.fetchBlockedUsers();
});

/// Action controller for unblocking. Invalidates [blockedUsersProvider] after a
/// successful unblock so the list refreshes.
class UnblockController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> unblock(String blockedId) async {
    state = const AsyncLoading();
    try {
      await ref.read(settingsRepositoryProvider).unblock(blockedId);
      ref.invalidate(blockedUsersProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final unblockControllerProvider =
    AutoDisposeAsyncNotifierProvider<UnblockController, void>(
  UnblockController.new,
);

/// User-facing notification preference toggles, persisted locally. These gate
/// which categories of push the device shows; the server still sends all types.
class NotificationPrefs {
  const NotificationPrefs({
    this.bookings = true,
    this.payments = true,
    this.chat = true,
    this.promotions = true,
  });

  final bool bookings;
  final bool payments;
  final bool chat;
  final bool promotions;

  NotificationPrefs copyWith({
    bool? bookings,
    bool? payments,
    bool? chat,
    bool? promotions,
  }) {
    return NotificationPrefs(
      bookings: bookings ?? this.bookings,
      payments: payments ?? this.payments,
      chat: chat ?? this.chat,
      promotions: promotions ?? this.promotions,
    );
  }

  String encode() => '${bookings ? 1 : 0}${payments ? 1 : 0}'
      '${chat ? 1 : 0}${promotions ? 1 : 0}';

  factory NotificationPrefs.decode(String? raw) {
    if (raw == null || raw.length < 4) return const NotificationPrefs();
    return NotificationPrefs(
      bookings: raw[0] == '1',
      payments: raw[1] == '1',
      chat: raw[2] == '1',
      promotions: raw[3] == '1',
    );
  }
}

/// Persists the [NotificationPrefs] across launches.
class NotificationPrefsNotifier extends StateNotifier<NotificationPrefs> {
  NotificationPrefsNotifier(this._storage)
      : super(const NotificationPrefs()) {
    _load();
  }

  final FlutterSecureStorage _storage;
  static const _key = 'cr_notification_prefs';

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    state = NotificationPrefs.decode(raw);
  }

  Future<void> _persist() async {
    await _storage.write(key: _key, value: state.encode());
  }

  Future<void> setBookings(bool v) async {
    state = state.copyWith(bookings: v);
    await _persist();
  }

  Future<void> setPayments(bool v) async {
    state = state.copyWith(payments: v);
    await _persist();
  }

  Future<void> setChat(bool v) async {
    state = state.copyWith(chat: v);
    await _persist();
  }

  Future<void> setPromotions(bool v) async {
    state = state.copyWith(promotions: v);
    await _persist();
  }
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>((ref) {
  return NotificationPrefsNotifier(ref.watch(_settingsStorageProvider));
});

/// Persisted app language preference. The app ships English; Hindi is offered
/// as a stored preference for future localisation.
class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier(this._storage) : super('English') {
    _load();
  }

  final FlutterSecureStorage _storage;
  static const _key = 'cr_language';

  static const List<String> supported = ['English', 'हिंदी'];

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    if (raw != null && supported.contains(raw)) state = raw;
  }

  Future<void> setLanguage(String language) async {
    if (!supported.contains(language)) return;
    state = language;
    await _storage.write(key: _key, value: language);
  }
}

final languageProvider =
    StateNotifierProvider<LanguageNotifier, String>((ref) {
  return LanguageNotifier(ref.watch(_settingsStorageProvider));
});
