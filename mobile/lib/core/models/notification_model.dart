import 'package:companion_ranchi/core/models/json_utils.dart';

/// An in-app notification (notifications table). Returned by
/// `GET /notifications` and pushed via the `notification:new` socket event.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.isRead = false,
    this.createdAt,
  });

  final String id;

  /// `BOOKING` | `PAYMENT` | `CHAT` | `SYSTEM` | `KYC` | `REVIEW` |
  /// `REFERRAL` | `SOS`.
  final String type;
  final String title;
  final String body;

  /// Free-form payload (e.g. `{ bookingId, conversationId }`) for deep links.
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: J.asString(json['id']),
        type: J.asString(json['type'], 'SYSTEM'),
        title: J.asString(json['title']),
        body: J.asString(json['body']),
        data: J.asMap(json['data']),
        isRead: J.asBool(json['isRead']),
        createdAt: J.asDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'data': data,
        'isRead': isRead,
        'createdAt': createdAt?.toIso8601String(),
      };

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}
