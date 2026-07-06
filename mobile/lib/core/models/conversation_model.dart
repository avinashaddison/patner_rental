import 'package:companion_ranchi/core/models/json_utils.dart';

/// A chat thread (conversations table). The list endpoint
/// (`GET /chat/conversations`) returns the peer's display info, the last
/// message preview and an unread count.
class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.customerId,
    required this.companionId,
    this.bookingId,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.lastMessageMine = false,
    this.peerUserId,
    this.peerName,
    this.peerPhotoUrl,
    this.peerIsOnline = false,
    this.peerLastActiveAt,
  });

  final String id;
  final String customerId;
  final String companionId;
  final String? bookingId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// True when the signed-in user sent the last message (for a "You:" preview).
  final bool lastMessageMine;

  /// The other participant relative to the current user (server-resolved).
  final String? peerUserId;
  final String? peerName;
  final String? peerPhotoUrl;
  final bool peerIsOnline;

  /// When the peer was last active (for "Active … ago"); null if unknown.
  final DateTime? peerLastActiveAt;

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    // Server may embed the peer as a `peer` object.
    final peer = J.asMap(json['peer']);
    return ConversationModel(
      id: J.asString(json['id']),
      customerId: J.asString(json['customerId']),
      companionId: J.asString(json['companionId']),
      bookingId: J.asStringOrNull(json['bookingId']),
      lastMessage: J.asStringOrNull(json['lastMessage']),
      lastMessageAt: J.asDate(json['lastMessageAt']),
      unreadCount: J.asInt(json['unreadCount']),
      lastMessageMine: J.asBool(json['lastMessageMine']),
      peerUserId: J.asStringOrNull(json['peerUserId']) ??
          J.asStringOrNull(peer['id']),
      peerName: J.asStringOrNull(json['peerName']) ??
          J.asStringOrNull(peer['name']) ??
          J.asStringOrNull(peer['fullName']),
      peerPhotoUrl: J.asStringOrNull(json['peerPhotoUrl']) ??
          J.asStringOrNull(peer['photoUrl']) ??
          J.asStringOrNull(peer['profilePhotoUrl']),
      peerIsOnline: J.asBool(json['peerIsOnline']) ||
          J.asBool(peer['isOnline']),
      peerLastActiveAt: J.asDate(json['peerLastActiveAt']) ??
          J.asDate(peer['lastActiveAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'companionId': companionId,
        'bookingId': bookingId,
        'lastMessage': lastMessage,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'unreadCount': unreadCount,
        'lastMessageMine': lastMessageMine,
        'peerUserId': peerUserId,
        'peerName': peerName,
        'peerPhotoUrl': peerPhotoUrl,
        'peerIsOnline': peerIsOnline,
        'peerLastActiveAt': peerLastActiveAt?.toIso8601String(),
      };

  ConversationModel copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? lastMessageMine,
    bool? peerIsOnline,
    DateTime? peerLastActiveAt,
  }) {
    return ConversationModel(
      id: id,
      customerId: customerId,
      companionId: companionId,
      bookingId: bookingId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageMine: lastMessageMine ?? this.lastMessageMine,
      peerUserId: peerUserId,
      peerName: peerName,
      peerPhotoUrl: peerPhotoUrl,
      peerIsOnline: peerIsOnline ?? this.peerIsOnline,
      peerLastActiveAt: peerLastActiveAt ?? this.peerLastActiveAt,
    );
  }
}
