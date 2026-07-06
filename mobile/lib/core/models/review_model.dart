import 'package:companion_ranchi/core/models/json_utils.dart';

/// A booking review (reviews table). Three sub-ratings (1..5) plus a derived
/// `overallRating`. Mirrors `POST /reviews` and
/// `GET /reviews/companion/:companionId`.
class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.companionId,
    required this.behaviourRating,
    required this.communicationRating,
    required this.punctualityRating,
    required this.overallRating,
    this.comment,
    this.customerName,
    this.customerPhotoUrl,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String customerId;
  final String companionId;

  final int behaviourRating;
  final int communicationRating;
  final int punctualityRating;

  /// Average of the three sub-ratings (server-computed).
  final double overallRating;
  final String? comment;

  /// Reviewer display data (often embedded for the reviews list).
  final String? customerName;
  final String? customerPhotoUrl;
  final DateTime? createdAt;

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    // The reviewer may be embedded as `customer: { fullName, profilePhotoUrl }`.
    final customer = J.asMap(json['customer']);
    return ReviewModel(
      id: J.asString(json['id']),
      bookingId: J.asString(json['bookingId']),
      customerId: J.asString(json['customerId']),
      companionId: J.asString(json['companionId']),
      behaviourRating: J.asInt(json['behaviourRating']),
      communicationRating: J.asInt(json['communicationRating']),
      punctualityRating: J.asInt(json['punctualityRating']),
      overallRating: J.asDouble(json['overallRating']),
      comment: J.asStringOrNull(json['comment']),
      customerName: J.asStringOrNull(json['customerName']) ??
          J.asStringOrNull(customer['fullName']),
      customerPhotoUrl: J.asStringOrNull(json['customerPhotoUrl']) ??
          J.asStringOrNull(customer['profilePhotoUrl']),
      createdAt: J.asDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'customerId': customerId,
        'companionId': companionId,
        'behaviourRating': behaviourRating,
        'communicationRating': communicationRating,
        'punctualityRating': punctualityRating,
        'overallRating': overallRating,
        'comment': comment,
        'customerName': customerName,
        'customerPhotoUrl': customerPhotoUrl,
        'createdAt': createdAt?.toIso8601String(),
      };
}
