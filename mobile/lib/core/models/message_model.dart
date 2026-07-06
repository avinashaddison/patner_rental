import 'package:companion_ranchi/core/models/json_utils.dart';

/// A chat message (messages table). `type` is `TEXT` or `IMAGE`. Used by both
/// the REST history endpoint and the `message:new` / `message:sent` socket
/// events.
class MessageModel {
  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    this.content,
    this.imageUrl,
    this.isRead = false,
    this.readAt,
    this.createdAt,
    this.tempId,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;

  /// `TEXT` | `IMAGE`.
  final String type;
  final String? content;
  final String? imageUrl;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  /// Optimistic client-side id, echoed back by the server in `message:sent`.
  final String? tempId;

  bool get isImage => type == 'IMAGE';
  bool get isText => type == 'TEXT';

  bool isMine(String myUserId) => senderId == myUserId;

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: J.asString(json['id']),
        conversationId: J.asString(json['conversationId']),
        senderId: J.asString(json['senderId']),
        receiverId: J.asString(json['receiverId']),
        type: J.asString(json['type'], 'TEXT'),
        content: J.asStringOrNull(json['content']),
        imageUrl: J.asStringOrNull(json['imageUrl']),
        isRead: J.asBool(json['isRead']),
        readAt: J.asDate(json['readAt']),
        createdAt: J.asDate(json['createdAt']),
        tempId: J.asStringOrNull(json['tempId']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'receiverId': receiverId,
        'type': type,
        'content': content,
        'imageUrl': imageUrl,
        'isRead': isRead,
        'readAt': readAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        if (tempId != null) 'tempId': tempId,
      };

  MessageModel copyWith({
    String? id,
    bool? isRead,
    DateTime? readAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      receiverId: receiverId,
      type: type,
      content: content,
      imageUrl: imageUrl,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
      tempId: tempId,
    );
  }
}
