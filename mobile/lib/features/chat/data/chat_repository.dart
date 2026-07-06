import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:companion_ranchi/core/models/conversation_model.dart';
import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/network/api_client.dart';
import 'package:companion_ranchi/core/network/uploads_repository.dart';

/// A page of chat history plus whether more older messages exist (for
/// upward/infinite scroll). The backend returns newest-first; we keep that
/// order at the data layer and let the UI reverse for display.
class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  final List<MessageModel> messages;
  final bool hasMore;
}

/// REST access for the chat domain (`/chat/*`). Realtime delivery is handled by
/// [SocketClient]; this repository covers conversation listing, history paging,
/// the REST send fallback, read-marking and media uploads via presign.
class ChatRepository {
  ChatRepository(this._api, this._uploads);

  final ApiClient _api;
  final UploadsRepository _uploads;

  /// `GET /chat/conversations` — list with last message + unread count.
  Future<List<ConversationModel>> fetchConversations() async {
    final data = await _api.getJson('/chat/conversations');
    return _asConversationList(data);
  }

  /// `POST /chat/conversations` — get-or-create a thread with [peerUserId].
  Future<ConversationModel> openConversation({
    required String peerUserId,
    String? bookingId,
  }) async {
    final data = await _api.postJson(
      '/chat/conversations',
      body: {
        'peerUserId': peerUserId,
        if (bookingId != null) 'bookingId': bookingId,
      },
    );
    return ConversationModel.fromJson(_asMap(data));
  }

  /// `GET /chat/conversations/:id/messages` — paginated history (newest-first).
  Future<MessagePage> fetchMessages(
    String conversationId, {
    int page = 1,
    int limit = 30,
  }) async {
    final envelope = await _api.getEnvelope(
      '/chat/conversations/$conversationId/messages',
      query: {'page': page, 'limit': limit, 'sort': 'createdAt:desc'},
    );
    final messages = _asMessageList(envelope['data']);
    final meta = envelope['meta'];
    final hasMore = _hasMore(meta, page, limit, messages.length);
    return MessagePage(messages: messages, hasMore: hasMore);
  }

  /// `POST /chat/conversations/:id/messages` — REST fallback when the socket is
  /// not connected. Prefer [SocketClient.sendMessage] for live delivery.
  Future<MessageModel> sendMessageRest({
    required String conversationId,
    required String type,
    String? content,
    String? imageUrl,
  }) async {
    final data = await _api.postJson(
      '/chat/conversations/$conversationId/messages',
      body: {
        'type': type,
        if (content != null) 'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
      },
    );
    return MessageModel.fromJson(_asMap(data));
  }

  /// `POST /chat/conversations/:id/read` — mark the peer's messages as read.
  Future<void> markRead(String conversationId) async {
    await _api.postJson('/chat/conversations/$conversationId/read');
  }

  /// Upload an image to R2 (folder `chat`) and return its public URL for
  /// sharing in a conversation. Delegates to the shared [UploadsRepository] so
  /// the presign → PUT(skipAuth) → status-check flow is identical everywhere.
  Future<String> uploadImage({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) {
    return _uploads.uploadBytes(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      folder: 'chat',
    );
  }

  // -- parsing helpers -------------------------------------------------------

  List<ConversationModel> _asConversationList(dynamic data) {
    final list = data is Map && data['items'] is List
        ? data['items'] as List
        : data is List
            ? data
            : const [];
    return list
        .whereType<Map>()
        .map((e) => ConversationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  List<MessageModel> _asMessageList(dynamic data) {
    final list = data is List
        ? data
        : data is Map && data['items'] is List
            ? data['items'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  bool _hasMore(dynamic meta, int page, int limit, int received) {
    if (meta is Map && meta['total'] != null) {
      final total = int.tryParse(meta['total'].toString()) ?? 0;
      return page * limit < total;
    }
    // Fallback: a full page implies there may be more.
    return received >= limit;
  }
}

/// App-wide [ChatRepository] provider, wired to the shared [ApiClient].
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(apiClientProvider),
    ref.watch(uploadsRepositoryProvider),
  );
});
