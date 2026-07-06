import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/auth/auth_controller.dart';
import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/socket/socket_client.dart';
import 'package:companion_ranchi/features/chat/data/chat_repository.dart';

/// Immutable view-state for a single chat thread.
///
/// [messages] is ordered **oldest -> newest**; the screen renders a reversed
/// `ListView` so new messages appear at the bottom. Optimistic (unsent)
/// messages carry a `tempId` and `isPending`/`failed` flags so the UI can show
/// a clock / retry affordance.
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.peerTyping = false,
    this.connected = false,
    this.sending = false,
    this.pendingTempIds = const {},
    this.failedTempIds = const {},
  });

  final List<MessageModel> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final bool peerTyping;
  final bool connected;
  final bool sending;

  /// Temp ids of optimistic messages awaiting server ack.
  final Set<String> pendingTempIds;

  /// Temp ids of optimistic messages that failed to send.
  final Set<String> failedTempIds;

  bool isPending(MessageModel m) =>
      m.tempId != null && pendingTempIds.contains(m.tempId);
  bool isFailed(MessageModel m) =>
      m.tempId != null && failedTempIds.contains(m.tempId);

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
    bool? peerTyping,
    bool? connected,
    bool? sending,
    Set<String>? pendingTempIds,
    Set<String>? failedTempIds,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      peerTyping: peerTyping ?? this.peerTyping,
      connected: connected ?? this.connected,
      sending: sending ?? this.sending,
      pendingTempIds: pendingTempIds ?? this.pendingTempIds,
      failedTempIds: failedTempIds ?? this.failedTempIds,
    );
  }
}

/// Drives one open chat thread: loads history (REST, paginated), streams live
/// events from [SocketClient], sends text/image messages optimistically, emits
/// typing start/stop, and marks the peer's messages read on open.
class ChatController
    extends AutoDisposeFamilyAsyncNotifier<ChatState, String> {
  static const int _pageSize = 30;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  SocketClient get _socket => ref.read(socketClientProvider);

  late final String _conversationId;
  late final String _myUserId;

  int _page = 1;
  bool _typingSent = false;
  Timer? _typingDebounce;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  Future<ChatState> build(String arg) async {
    _conversationId = arg;
    _myUserId = ref.read(currentUserProvider)?.id ?? '';

    unawaited(_socket.connect());

    _subs
      ..add(_socket.onMessage.listen(_onIncoming))
      ..add(_socket.onMessageSent.listen(_onSentAck))
      ..add(_socket.onTyping.listen(_onTyping))
      ..add(_socket.onRead.listen(_onRead))
      ..add(_socket.onConnectionChange.listen(_onConnection));

    ref.onDispose(() {
      _typingDebounce?.cancel();
      if (_typingSent) _socket.stopTyping(_conversationId);
      for (final s in _subs) {
        s.cancel();
      }
    });

    final page = await _repo.fetchMessages(
      _conversationId,
      page: _page,
      limit: _pageSize,
    );

    // Mark the thread read on open (best-effort) and notify the peer.
    _socket.markRead(_conversationId);
    unawaited(_safeMarkRead());

    // Server returns newest-first; reverse to oldest-first for display.
    final ordered = page.messages.reversed.toList();
    return ChatState(
      messages: ordered,
      isLoading: false,
      hasMore: page.hasMore,
      connected: _socket.isConnected,
    );
  }

  ChatState get _state =>
      state.valueOrNull ?? const ChatState(isLoading: false);

  // -- history paging --------------------------------------------------------

  /// Load the next (older) page of history. Called when the user scrolls to the
  /// top of the thread.
  Future<void> loadMore() async {
    final current = _state;
    if (current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await _repo.fetchMessages(
        _conversationId,
        page: _page + 1,
        limit: _pageSize,
      );
      _page += 1;
      final older = next.messages.reversed.toList();
      // Prepend older messages, de-duplicating on id.
      final existingIds = current.messages.map((m) => m.id).toSet();
      final merged = [
        ...older.where((m) => !existingIds.contains(m.id)),
        ...current.messages,
      ];
      state = AsyncData(
        current.copyWith(
          messages: merged,
          isLoadingMore: false,
          hasMore: next.hasMore,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  // -- sending ---------------------------------------------------------------

  /// Send a text message optimistically. The bubble appears immediately with a
  /// pending clock; the server's `message:sent` ack swaps in the persisted row.
  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _send(type: 'TEXT', content: trimmed);
  }

  /// Send a previously uploaded image (publicUrl from [uploadAndSendImage]).
  Future<void> _sendImageUrl(String imageUrl) async {
    await _send(type: 'IMAGE', imageUrl: imageUrl);
  }

  Future<void> _send({
    required String type,
    String? content,
    String? imageUrl,
  }) async {
    final current = _state;
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = MessageModel(
      id: tempId,
      conversationId: _conversationId,
      senderId: _myUserId,
      receiverId: '',
      type: type,
      content: content,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
      tempId: tempId,
    );

    // Stop typing the moment we send.
    _cancelTyping();

    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, optimistic],
        pendingTempIds: {...current.pendingTempIds, tempId},
        clearError: true,
      ),
    );

    if (_socket.isConnected) {
      _socket.sendMessage(
        conversationId: _conversationId,
        type: type,
        content: content,
        imageUrl: imageUrl,
        tempId: tempId,
      );
      // The `message:sent` ack reconciles state. A safety timer marks the
      // message failed if no ack arrives.
      _scheduleAckTimeout(tempId);
    } else {
      // Offline / socket down: fall back to the REST endpoint.
      await _sendViaRest(
        tempId: tempId,
        type: type,
        content: content,
        imageUrl: imageUrl,
      );
    }
  }

  Future<void> _sendViaRest({
    required String tempId,
    required String type,
    String? content,
    String? imageUrl,
  }) async {
    try {
      final saved = await _repo.sendMessageRest(
        conversationId: _conversationId,
        type: type,
        content: content,
        imageUrl: imageUrl,
      );
      _reconcile(tempId, saved);
    } catch (_) {
      _markFailed(tempId);
    }
  }

  void _scheduleAckTimeout(String tempId) {
    Timer(const Duration(seconds: 8), () {
      final s = _state;
      if (s.pendingTempIds.contains(tempId)) {
        _markFailed(tempId);
      }
    });
  }

  /// Retry a previously failed optimistic message.
  Future<void> retry(MessageModel message) async {
    final tempId = message.tempId;
    if (tempId == null) return;
    final current = _state;
    // Move it back to pending.
    state = AsyncData(
      current.copyWith(
        failedTempIds: {...current.failedTempIds}..remove(tempId),
        pendingTempIds: {...current.pendingTempIds, tempId},
      ),
    );
    if (_socket.isConnected) {
      _socket.sendMessage(
        conversationId: _conversationId,
        type: message.type,
        content: message.content,
        imageUrl: message.imageUrl,
        tempId: tempId,
      );
      _scheduleAckTimeout(tempId);
    } else {
      await _sendViaRest(
        tempId: tempId,
        type: message.type,
        content: message.content,
        imageUrl: message.imageUrl,
      );
    }
  }

  // -- image upload ----------------------------------------------------------

  /// Upload picked image bytes to R2 (presign) then send as an IMAGE message.
  Future<void> uploadAndSendImage({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    final current = _state;
    state = AsyncData(current.copyWith(sending: true, clearError: true));
    try {
      final url = await _repo.uploadImage(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
      );
      state = AsyncData(_state.copyWith(sending: false));
      await _sendImageUrl(url);
    } on ApiException catch (e) {
      state = AsyncData(_state.copyWith(sending: false, error: e));
    } catch (e) {
      state = AsyncData(_state.copyWith(sending: false, error: e));
    }
  }

  // -- typing ----------------------------------------------------------------

  /// Call on every keystroke. Emits `typing:start` once, then `typing:stop`
  /// after a short idle period (debounced).
  void onInputChanged(String text) {
    if (text.trim().isEmpty) {
      _cancelTyping();
      return;
    }
    if (!_typingSent) {
      _typingSent = true;
      _socket.startTyping(_conversationId);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), _cancelTyping);
  }

  void _cancelTyping() {
    _typingDebounce?.cancel();
    _typingDebounce = null;
    if (_typingSent) {
      _typingSent = false;
      _socket.stopTyping(_conversationId);
    }
  }

  // -- incoming socket events ------------------------------------------------

  void _onIncoming(MessageModel message) {
    if (message.conversationId != _conversationId) return;
    final current = _state;

    // Ignore our own echoes (handled by the `message:sent` ack path).
    if (message.senderId == _myUserId) {
      // It may still be our message arriving via message:new without a tempId;
      // de-dup on id.
      if (current.messages.any((m) => m.id == message.id)) return;
    }
    if (current.messages.any((m) => m.id == message.id)) return;

    final next = [...current.messages, message];
    state = AsyncData(current.copyWith(messages: next));

    // We're looking at the thread: immediately acknowledge as read.
    if (message.senderId != _myUserId) {
      _socket.markRead(_conversationId);
      unawaited(_safeMarkRead());
    }
  }

  void _onSentAck(MessageSentEvent event) {
    final tempId = event.tempId;
    if (event.message.conversationId != _conversationId) return;
    if (tempId == null) {
      // No temp id to reconcile: treat as a fresh incoming for our own message.
      final current = _state;
      if (!current.messages.any((m) => m.id == event.message.id)) {
        state = AsyncData(
          current.copyWith(messages: [...current.messages, event.message]),
        );
      }
      return;
    }
    _reconcile(tempId, event.message);
  }

  void _onTyping(TypingEvent event) {
    if (event.conversationId != _conversationId) return;
    if (event.userId == _myUserId) return;
    state = AsyncData(_state.copyWith(peerTyping: event.isTyping));
  }

  void _onRead(ReadEvent event) {
    if (event.conversationId != _conversationId) return;
    if (event.userId == _myUserId) return;
    // The peer read our messages: flip our sent messages to read.
    final current = _state;
    final next = current.messages.map((m) {
      if (m.senderId == _myUserId && !m.isRead) {
        return m.copyWith(isRead: true, readAt: DateTime.now());
      }
      return m;
    }).toList();
    state = AsyncData(current.copyWith(messages: next));
  }

  void _onConnection(bool connected) {
    state = AsyncData(_state.copyWith(connected: connected));
  }

  // -- helpers ---------------------------------------------------------------

  /// Replace the optimistic message [tempId] with the persisted [saved] row.
  void _reconcile(String tempId, MessageModel saved) {
    final current = _state;
    final idx = current.messages.indexWhere((m) => m.tempId == tempId);
    final next = [...current.messages];
    if (idx != -1) {
      next[idx] = saved;
    } else if (!next.any((m) => m.id == saved.id)) {
      next.add(saved);
    }
    state = AsyncData(
      current.copyWith(
        messages: next,
        pendingTempIds: {...current.pendingTempIds}..remove(tempId),
        failedTempIds: {...current.failedTempIds}..remove(tempId),
      ),
    );
  }

  void _markFailed(String tempId) {
    final current = _state;
    state = AsyncData(
      current.copyWith(
        pendingTempIds: {...current.pendingTempIds}..remove(tempId),
        failedTempIds: {...current.failedTempIds, tempId},
      ),
    );
  }

  Future<void> _safeMarkRead() async {
    try {
      await _repo.markRead(_conversationId);
    } catch (_) {
      // Non-fatal: socket already emitted message:read.
    }
  }
}

final chatControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ChatController, ChatState, String>(ChatController.new);
