import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/conversation_model.dart';
import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/core/utils/app_sounds.dart';
import 'package:companion_ranchi/features/chat/data/chat_repository.dart';

/// Loads the conversation list and keeps it live: incoming `message:new` socket
/// events bump the matching thread's last-message preview and unread count and
/// re-sort the list; `presence:update` flips the peer's online dot.
class ConversationsController
    extends AutoDisposeAsyncNotifier<List<ConversationModel>> {
  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  SocketClient get _socket => ref.read(socketClientProvider);

  late final String _myUserId;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  Future<List<ConversationModel>> build() async {
    _myUserId = ref.read(currentUserProvider)?.id ?? '';

    // Ensure the realtime channel is up so the list stays fresh.
    unawaited(_socket.connect());

    _subs
      ..add(_socket.onMessage.listen(_onIncomingMessage))
      ..add(_socket.onPresence.listen(_onPresence))
      ..add(_socket.onConnectionChange.listen(_onConnectionChange));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
    });

    return _repo.fetchConversations();
  }

  /// Pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.fetchConversations);
  }

  /// Total unread across all threads (for the bottom-nav badge).
  int get totalUnread {
    final list = state.valueOrNull;
    if (list == null) return 0;
    return list.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  void _onIncomingMessage(MessageModel message) {
    // Ding for messages from OTHERS (server only pushes message:new to the
    // receiver, but guard anyway). Debounced inside AppSounds.
    if (message.senderId != _myUserId) {
      AppSounds.notification();
    }

    final list = state.valueOrNull;
    if (list == null) return;

    final idx =
        list.indexWhere((c) => c.id == message.conversationId);
    if (idx == -1) {
      // A brand-new thread we haven't loaded yet: refetch quietly.
      unawaited(_silentRefresh());
      return;
    }

    final existing = list[idx];
    final isIncoming = message.senderId != _myUserId;
    final updated = existing.copyWith(
      lastMessage: _preview(message),
      lastMessageAt: message.createdAt ?? DateTime.now(),
      unreadCount:
          isIncoming ? existing.unreadCount + 1 : existing.unreadCount,
    );

    final next = [...list]
      ..removeAt(idx)
      ..insert(0, updated);
    state = AsyncData(next);
  }

  void _onPresence(PresenceEvent event) {
    final list = state.valueOrNull;
    if (list == null) return;
    var changed = false;
    final next = list.map((c) {
      if (c.peerUserId == event.userId &&
          c.peerIsOnline != event.isOnline) {
        changed = true;
        return c.copyWith(peerIsOnline: event.isOnline);
      }
      return c;
    }).toList();
    if (changed) state = AsyncData(next);
  }

  void _onConnectionChange(bool connected) {
    // On reconnect, resync the list so we don't miss anything sent while down.
    if (connected && state.hasValue) {
      unawaited(_silentRefresh());
    }
  }

  /// Locally zero a thread's unread count (e.g. after opening it).
  void markThreadRead(String conversationId) {
    final list = state.valueOrNull;
    if (list == null) return;
    final idx = list.indexWhere((c) => c.id == conversationId);
    if (idx == -1 || list[idx].unreadCount == 0) return;
    final next = [...list];
    next[idx] = next[idx].copyWith(unreadCount: 0);
    state = AsyncData(next);
  }

  Future<void> _silentRefresh() async {
    try {
      final fresh = await _repo.fetchConversations();
      state = AsyncData(fresh);
    } catch (_) {
      // Keep the current list on a transient refresh error.
    }
  }

  String _preview(MessageModel m) {
    if (m.isImage) return '📷 Photo';
    final c = m.content?.trim();
    return (c == null || c.isEmpty) ? 'Message' : c;
  }
}

final conversationsControllerProvider = AutoDisposeAsyncNotifierProvider<
    ConversationsController, List<ConversationModel>>(
  ConversationsController.new,
);

/// Convenience: total unread messages across all conversations (badge source).
final totalUnreadChatProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(conversationsControllerProvider).valueOrNull;
  if (list == null) return 0;
  return list.fold<int>(0, (sum, c) => sum + c.unreadCount);
});
