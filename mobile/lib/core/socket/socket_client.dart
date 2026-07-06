import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:companion_ranchi/core/env/env.dart';
import 'package:companion_ranchi/core/models/message_model.dart';
import 'package:companion_ranchi/core/models/notification_model.dart';
import 'package:companion_ranchi/core/storage/token_storage.dart';

/// Typing indicator payload (`typing` server event).
class TypingEvent {
  const TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
  });
  final String conversationId;
  final String userId;
  final bool isTyping;
}

/// Read-receipt payload (`message:read` server event).
class ReadEvent {
  const ReadEvent({required this.conversationId, required this.userId});
  final String conversationId;
  final String userId;
}

/// Presence payload (`presence:update` server event).
class PresenceEvent {
  const PresenceEvent({required this.userId, required this.isOnline});
  final String userId;
  final bool isOnline;
}

/// Echoed temp id + persisted message (`message:sent` server event).
class MessageSentEvent {
  const MessageSentEvent({required this.tempId, required this.message});
  final String? tempId;
  final MessageModel message;
}

/// A peer's live-location ping during an active booking (`location:update`).
class LocationUpdateEvent {
  const LocationUpdateEvent({
    required this.bookingId,
    required this.userId,
    required this.lat,
    required this.lng,
    this.heading,
    this.speed,
    this.accuracy,
    this.at,
  });
  final String bookingId;
  final String userId;
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final DateTime? at;
}

/// Peer started or stopped sharing live location
/// (`location:peer-active` / `location:peer-stop`).
class LocationPeerEvent {
  const LocationPeerEvent({
    required this.bookingId,
    required this.userId,
    required this.active,
  });
  final String bookingId;
  final String userId;
  final bool active;
}

/// An incoming call ring (`call:incoming` server event).
class IncomingCallEvent {
  const IncomingCallEvent({
    required this.callId,
    required this.conversationId,
    required this.video,
    required this.fromUserId,
    required this.fromName,
    this.fromPhotoUrl,
  });
  final String callId;
  final String conversationId;
  final bool video;
  final String fromUserId;
  final String fromName;
  final String? fromPhotoUrl;
}

/// A call state relay (`call:accepted` / `call:rejected` / `call:cancelled` /
/// `call:ended`).
class CallStateEvent {
  const CallStateEvent({required this.callId, required this.conversationId});
  final String callId;
  final String conversationId;
}

/// A live support-chat message pushed from staff (`support:message` event).
class SupportSocketMessage {
  const SupportSocketMessage({
    required this.ticketId,
    required this.id,
    required this.message,
    required this.role,
    this.createdAt,
  });
  final String ticketId;
  final String id;
  final String message;
  final String role; // USER | SUPPORT
  final DateTime? createdAt;
}

/// Authenticated Socket.IO client wrapping the realtime contract from API.md.
///
/// Client -> server: `message:send`, `typing:start`, `typing:stop`,
///   `message:read`, `presence:ping`.
/// Server -> client: `message:new`, `message:sent`, `typing`, `message:read`,
///   `presence:update`, `notification:new`.
///
/// Exposes broadcast streams that feature controllers can subscribe to.
class SocketClient {
  SocketClient(this._tokens);

  final TokenStorage _tokens;
  io.Socket? _socket;

  final _newMessages = StreamController<MessageModel>.broadcast();
  final _sentMessages = StreamController<MessageSentEvent>.broadcast();
  final _typing = StreamController<TypingEvent>.broadcast();
  final _reads = StreamController<ReadEvent>.broadcast();
  final _presence = StreamController<PresenceEvent>.broadcast();
  final _notifications = StreamController<NotificationModel>.broadcast();
  final _supportMessages = StreamController<SupportSocketMessage>.broadcast();
  final _locationUpdates = StreamController<LocationUpdateEvent>.broadcast();
  final _locationPeer = StreamController<LocationPeerEvent>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final _incomingCalls = StreamController<IncomingCallEvent>.broadcast();
  final _callAccepted = StreamController<CallStateEvent>.broadcast();
  final _callRejected = StreamController<CallStateEvent>.broadcast();
  final _callCancelled = StreamController<CallStateEvent>.broadcast();
  final _callEnded = StreamController<CallStateEvent>.broadcast();

  Stream<MessageModel> get onMessage => _newMessages.stream;
  Stream<MessageSentEvent> get onMessageSent => _sentMessages.stream;
  Stream<TypingEvent> get onTyping => _typing.stream;
  Stream<ReadEvent> get onRead => _reads.stream;
  Stream<PresenceEvent> get onPresence => _presence.stream;
  Stream<NotificationModel> get onNotification => _notifications.stream;
  Stream<SupportSocketMessage> get onSupportMessage => _supportMessages.stream;
  Stream<LocationUpdateEvent> get onLocationUpdate => _locationUpdates.stream;
  Stream<LocationPeerEvent> get onLocationPeer => _locationPeer.stream;
  Stream<bool> get onConnectionChange => _connection.stream;
  Stream<IncomingCallEvent> get onIncomingCall => _incomingCalls.stream;
  Stream<CallStateEvent> get onCallAccepted => _callAccepted.stream;
  Stream<CallStateEvent> get onCallRejected => _callRejected.stream;
  Stream<CallStateEvent> get onCallCancelled => _callCancelled.stream;
  Stream<CallStateEvent> get onCallEnded => _callEnded.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Connect using the stored access token. Safe to call repeatedly.
  Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;
    final token = await _tokens.readAccessToken();
    if (token == null || token.isEmpty) return;

    _socket?.dispose();

    final socket = io.io(
      Env.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1500)
          .build(),
    );

    socket.onConnect((_) => _connection.add(true));
    socket.onDisconnect((_) => _connection.add(false));
    socket.onConnectError((_) => _connection.add(false));

    socket.on('message:new', (data) {
      final map = _extractMessageMap(data);
      if (map != null) _newMessages.add(MessageModel.fromJson(map));
    });

    socket.on('message:sent', (data) {
      if (data is Map) {
        final m = data['message'];
        if (m is Map) {
          _sentMessages.add(
            MessageSentEvent(
              tempId: data['tempId']?.toString(),
              message: MessageModel.fromJson(Map<String, dynamic>.from(m)),
            ),
          );
        }
      }
    });

    socket.on('typing', (data) {
      if (data is Map) {
        _typing.add(
          TypingEvent(
            conversationId: data['conversationId']?.toString() ?? '',
            userId: data['userId']?.toString() ?? '',
            isTyping: data['isTyping'] == true,
          ),
        );
      }
    });

    socket.on('message:read', (data) {
      if (data is Map) {
        _reads.add(
          ReadEvent(
            conversationId: data['conversationId']?.toString() ?? '',
            userId: data['userId']?.toString() ?? '',
          ),
        );
      }
    });

    socket.on('presence:update', (data) {
      if (data is Map) {
        _presence.add(
          PresenceEvent(
            userId: data['userId']?.toString() ?? '',
            isOnline: data['isOnline'] == true,
          ),
        );
      }
    });

    socket.on('notification:new', (data) {
      if (data is Map && data['notification'] is Map) {
        _notifications.add(
          NotificationModel.fromJson(
            Map<String, dynamic>.from(data['notification'] as Map),
          ),
        );
      }
    });

    socket.on('support:message', (data) {
      if (data is Map && data['message'] is Map) {
        final m = Map<String, dynamic>.from(data['message'] as Map);
        _supportMessages.add(
          SupportSocketMessage(
            ticketId: data['ticketId']?.toString() ?? '',
            id: m['id']?.toString() ?? '',
            message: m['message']?.toString() ?? '',
            role: m['role']?.toString() ?? 'SUPPORT',
            createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? ''),
          ),
        );
      }
    });

    socket.on('location:update', (data) {
      if (data is Map) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return;
        _locationUpdates.add(
          LocationUpdateEvent(
            bookingId: data['bookingId']?.toString() ?? '',
            userId: data['userId']?.toString() ?? '',
            lat: lat,
            lng: lng,
            heading: (data['heading'] as num?)?.toDouble(),
            speed: (data['speed'] as num?)?.toDouble(),
            accuracy: (data['accuracy'] as num?)?.toDouble(),
            at: DateTime.tryParse(data['at']?.toString() ?? ''),
          ),
        );
      }
    });

    socket.on('location:peer-active', (data) {
      if (data is Map) {
        _locationPeer.add(
          LocationPeerEvent(
            bookingId: data['bookingId']?.toString() ?? '',
            userId: data['userId']?.toString() ?? '',
            active: true,
          ),
        );
      }
    });

    socket.on('call:incoming', (data) {
      if (data is Map) {
        final from = data['from'] is Map
            ? Map<String, dynamic>.from(data['from'] as Map)
            : const <String, dynamic>{};
        _incomingCalls.add(
          IncomingCallEvent(
            callId: data['callId']?.toString() ?? '',
            conversationId: data['conversationId']?.toString() ?? '',
            video: data['video'] == true,
            fromUserId: from['id']?.toString() ?? '',
            fromName: from['name']?.toString() ?? 'Incoming call',
            fromPhotoUrl: from['photoUrl']?.toString(),
          ),
        );
      }
    });

    void bindCallState(String event, StreamController<CallStateEvent> sink) {
      socket.on(event, (data) {
        if (data is Map) {
          sink.add(CallStateEvent(
            callId: data['callId']?.toString() ?? '',
            conversationId: data['conversationId']?.toString() ?? '',
          ));
        }
      });
    }

    bindCallState('call:accepted', _callAccepted);
    bindCallState('call:rejected', _callRejected);
    bindCallState('call:cancelled', _callCancelled);
    bindCallState('call:ended', _callEnded);

    socket.on('location:peer-stop', (data) {
      if (data is Map) {
        _locationPeer.add(
          LocationPeerEvent(
            bookingId: data['bookingId']?.toString() ?? '',
            userId: data['userId']?.toString() ?? '',
            active: false,
          ),
        );
      }
    });

    _socket = socket;
    socket.connect();
  }

  Map<String, dynamic>? _extractMessageMap(dynamic data) {
    if (data is Map && data['message'] is Map) {
      return Map<String, dynamic>.from(data['message'] as Map);
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  // ---- Client -> server emitters ----

  void sendMessage({
    required String conversationId,
    required String type,
    String? content,
    String? imageUrl,
    String? tempId,
  }) {
    _socket?.emit('message:send', {
      'conversationId': conversationId,
      'type': type,
      if (content != null) 'content': content,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (tempId != null) 'tempId': tempId,
    });
  }

  void startTyping(String conversationId) =>
      _socket?.emit('typing:start', {'conversationId': conversationId});

  void stopTyping(String conversationId) =>
      _socket?.emit('typing:stop', {'conversationId': conversationId});

  void markRead(String conversationId) =>
      _socket?.emit('message:read', {'conversationId': conversationId});

  void presencePing() => _socket?.emit('presence:ping');

  // ---- Voice/video call signaling (conversation-scoped) ----

  /// Ring the conversation peer. Server replies to the peer with
  /// `call:incoming`; we then hear `call:accepted` / `call:rejected`.
  void callInvite({
    required String callId,
    required String conversationId,
    required bool video,
  }) {
    _socket?.emit('call:invite', {
      'callId': callId,
      'conversationId': conversationId,
      'video': video,
    });
  }

  void callAccept({required String callId, required String conversationId}) =>
      _socket?.emit('call:accept', {
        'callId': callId,
        'conversationId': conversationId,
      });

  void callReject({required String callId, required String conversationId}) =>
      _socket?.emit('call:reject', {
        'callId': callId,
        'conversationId': conversationId,
      });

  /// Caller hangs up before the peer answers.
  void callCancel({required String callId, required String conversationId}) =>
      _socket?.emit('call:cancel', {
        'callId': callId,
        'conversationId': conversationId,
      });

  /// Either side hangs up an ongoing call.
  void callEnd({required String callId, required String conversationId}) =>
      _socket?.emit('call:end', {
        'callId': callId,
        'conversationId': conversationId,
      });

  // ---- Live location (booking-scoped) ----

  /// Announce intent to share live location for [bookingId]. The server
  /// authorises (participant + booking in CONFIRMED/IN_PROGRESS) and notifies
  /// the peer. Call once before the first [sendLocation].
  void joinLocation(String bookingId) =>
      _socket?.emit('location:join', {'bookingId': bookingId});

  /// Push one GPS fix to the booking peer.
  void sendLocation({
    required String bookingId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
  }) {
    _socket?.emit('location:update', {
      'bookingId': bookingId,
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  /// Stop sharing live location for [bookingId]; the peer is notified.
  void stopLocation(String bookingId) =>
      _socket?.emit('location:stop', {'bookingId': bookingId});

  /// Disconnect (e.g. on logout) without disposing the streams.
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connection.add(false);
  }

  void dispose() {
    disconnect();
    _newMessages.close();
    _sentMessages.close();
    _typing.close();
    _reads.close();
    _presence.close();
    _notifications.close();
    _supportMessages.close();
    _locationUpdates.close();
    _locationPeer.close();
    _connection.close();
    _incomingCalls.close();
    _callAccepted.close();
    _callRejected.close();
    _callCancelled.close();
    _callEnded.close();
  }
}

/// App-wide [SocketClient] provider. Disposes the socket when no longer used.
final socketClientProvider = Provider<SocketClient>((ref) {
  final client = SocketClient(ref.watch(tokenStorageProvider));
  ref.onDispose(client.dispose);
  return client;
});
