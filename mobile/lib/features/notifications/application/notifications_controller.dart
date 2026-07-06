import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/notification_model.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/features/notifications/data/notifications_repository.dart';

/// View-state for the notifications list (paginated + live).
@immutable
class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.page = 1,
    this.error,
  });

  final List<NotificationModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final Object? error;

  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationsState copyWith({
    List<NotificationModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    Object? error,
    bool clearError = false,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads notifications (`GET /notifications`), supports infinite scroll, marks
/// items read individually or all at once, and prepends live `notification:new`
/// socket pushes.
class NotificationsController
    extends AutoDisposeAsyncNotifier<NotificationsState> {
  static const int _pageSize = 20;

  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);
  SocketClient get _socket => ref.read(socketClientProvider);

  StreamSubscription<NotificationModel>? _sub;

  @override
  Future<NotificationsState> build() async {
    unawaited(_socket.connect());
    _sub = _socket.onNotification.listen(_onPush);
    ref.onDispose(() => _sub?.cancel());

    final page = await _repo.fetch(page: 1, limit: _pageSize);
    return NotificationsState(
      items: page.items,
      isLoading: false,
      hasMore: page.hasMore,
      page: 1,
    );
  }

  NotificationsState get _state =>
      state.valueOrNull ?? const NotificationsState(isLoading: false);

  /// Pull-to-refresh: reload the first page.
  Future<void> refresh() async {
    try {
      final page = await _repo.fetch(page: 1, limit: _pageSize);
      state = AsyncData(
        NotificationsState(
          items: page.items,
          isLoading: false,
          hasMore: page.hasMore,
          page: 1,
        ),
      );
    } catch (e) {
      state = AsyncData(_state.copyWith(error: e));
    }
  }

  /// Load the next page of older notifications.
  Future<void> loadMore() async {
    final current = _state;
    if (current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await _repo.fetch(page: current.page + 1, limit: _pageSize);
      final existingIds = current.items.map((n) => n.id).toSet();
      final merged = [
        ...current.items,
        ...next.items.where((n) => !existingIds.contains(n.id)),
      ];
      state = AsyncData(
        current.copyWith(
          items: merged,
          isLoadingMore: false,
          hasMore: next.hasMore,
          page: current.page + 1,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Mark a single notification read (optimistic).
  Future<void> markRead(String id) async {
    final current = _state;
    final idx = current.items.indexWhere((n) => n.id == id);
    if (idx == -1 || current.items[idx].isRead) return;
    final next = [...current.items];
    next[idx] = next[idx].copyWith(isRead: true);
    state = AsyncData(current.copyWith(items: next));
    try {
      await _repo.markRead(id);
    } catch (_) {
      // Revert on failure.
      final reverted = [..._state.items];
      final i = reverted.indexWhere((n) => n.id == id);
      if (i != -1) reverted[i] = reverted[i].copyWith(isRead: false);
      state = AsyncData(_state.copyWith(items: reverted));
    }
  }

  /// Mark every notification read (optimistic).
  Future<void> markAllRead() async {
    final current = _state;
    if (current.unreadCount == 0) return;
    final next =
        current.items.map((n) => n.copyWith(isRead: true)).toList();
    state = AsyncData(current.copyWith(items: next));
    try {
      await _repo.markAllRead();
    } catch (_) {
      // On failure, refetch authoritative state.
      await refresh();
    }
  }

  void _onPush(NotificationModel notification) {
    final current = _state;
    if (current.items.any((n) => n.id == notification.id)) return;
    state = AsyncData(
      current.copyWith(items: [notification, ...current.items]),
    );
  }
}

final notificationsControllerProvider = AutoDisposeAsyncNotifierProvider<
    NotificationsController, NotificationsState>(
  NotificationsController.new,
);

/// Unread notification count for the app-bar bell badge. Backed by the live
/// list when loaded; otherwise it polls the dedicated count endpoint.
///
/// REALTIME: subscribes to the socket's `notification:new` stream — each push
/// plays the notification sound and re-fetches the count, so the badge number
/// updates the moment a notification lands (no refresh needed).
final unreadNotificationCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final socket = ref.watch(socketClientProvider);
  unawaited(socket.connect());
  final sub = socket.onNotification.listen((_) {
    AppSounds.notification();
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final listState = ref.watch(notificationsControllerProvider).valueOrNull;
  if (listState != null) {
    return listState.unreadCount;
  }
  return ref.read(notificationsRepositoryProvider).unreadCount();
});
