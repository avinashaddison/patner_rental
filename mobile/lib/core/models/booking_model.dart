import 'package:companion_ranchi/core/models/json_utils.dart';
import 'package:companion_ranchi/core/models/payment_model.dart';

/// One entry in a booking's status history (booking_status_history).
class BookingStatusEntry {
  const BookingStatusEntry({
    required this.status,
    this.note,
    this.createdAt,
  });

  final String status;
  final String? note;
  final DateTime? createdAt;

  factory BookingStatusEntry.fromJson(Map<String, dynamic> json) =>
      BookingStatusEntry(
        status: J.asString(json['status']),
        note: J.asStringOrNull(json['note']),
        createdAt: J.asDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
      };
}

/// Lightweight party summary embedded in a booking (companion or customer).
class BookingParty {
  const BookingParty({
    required this.id,
    required this.name,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? photoUrl;

  factory BookingParty.fromJson(Map<String, dynamic> json) => BookingParty(
        id: J.asString(json['id']),
        name: J.asString(
          json['name'] ?? json['fullName'] ?? json['companionName'],
          'User',
        ),
        photoUrl: J.asStringOrNull(
          json['photoUrl'] ?? json['profilePhotoUrl'],
        ),
      );
}

/// All booking statuses (mirrors `BookingStatus`).
class BookingStatus {
  BookingStatus._();
  static const pending = 'PENDING';
  static const confirmed = 'CONFIRMED';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const refunded = 'REFUNDED';

  static const active = [pending, confirmed, inProgress];
  static const past = [completed, cancelled, refunded];

  static String label(String status) {
    switch (status) {
      case pending:
        return 'Pending';
      case confirmed:
        return 'Confirmed';
      case inProgress:
        return 'In Progress';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      case refunded:
        return 'Refunded';
      default:
        return status;
    }
  }
}

/// A booking (bookings table). Includes the money snapshot and, on the detail
/// endpoint, the [statusHistory] and [payment].
class BookingModel {
  const BookingModel({
    required this.id,
    required this.bookingCode,
    required this.customerId,
    required this.companionId,
    required this.activity,
    required this.durationHours,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    required this.meetingLocation,
    required this.meetingPlaceType,
    required this.hourlyRate,
    required this.totalAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.companionPayout,
    required this.status,
    this.categoryId,
    this.notes,
    this.cancellationReason,
    this.completedAt,
    this.createdAt,
    this.companion,
    this.customer,
    this.payment,
    this.statusHistory = const [],
    this.hasReview = false,
    this.startCode,
    this.startedAt,
  });

  final String id;
  final String bookingCode;
  final String customerId;
  final String companionId;
  final String? categoryId;
  final String activity;

  /// 1 | 2 | 4 | 6.
  final int durationHours;
  final DateTime? bookingDate;
  final String startTime; // "HH:mm"
  final String endTime; // "HH:mm"
  final String meetingLocation;

  /// Must be a public place type (SAFETY.md).
  final String meetingPlaceType;

  // Money snapshot (Decimal in INR).
  final double hourlyRate;
  final double totalAmount;
  final double commissionRate;
  final double commissionAmount;
  final double companionPayout;

  final String status;
  final String? notes;
  final String? cancellationReason;
  final DateTime? completedAt;
  final DateTime? createdAt;

  final BookingParty? companion;
  final BookingParty? customer;
  final PaymentModel? payment;
  final List<BookingStatusEntry> statusHistory;
  final bool hasReview;

  /// The 6-digit meet-at-location start code. Present only for the CUSTOMER
  /// (and admin) on a CONFIRMED booking — the companion never receives it.
  final String? startCode;

  /// The real-world timestamp when the meetup actually started (code verified).
  final DateTime? startedAt;

  bool get isPending => status == BookingStatus.pending;
  bool get isConfirmed => status == BookingStatus.confirmed;
  bool get isInProgress => status == BookingStatus.inProgress;
  bool get isCompleted => status == BookingStatus.completed;
  bool get isCancelled => status == BookingStatus.cancelled;
  bool get isRefunded => status == BookingStatus.refunded;
  bool get isActive => BookingStatus.active.contains(status);

  /// Whether the customer still needs to pay (PENDING + payment not captured).
  bool get awaitingPayment =>
      isPending && (payment == null || !payment!.isCaptured);

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    return BookingModel(
      id: J.asString(json['id']),
      bookingCode: J.asString(json['bookingCode']),
      customerId: J.asString(json['customerId']),
      companionId: J.asString(json['companionId']),
      categoryId: J.asStringOrNull(json['categoryId']),
      activity: J.asString(json['activity']),
      durationHours: J.asInt(json['durationHours'], 1),
      bookingDate: J.asDate(json['bookingDate']),
      startTime: J.asString(json['startTime']),
      endTime: J.asString(json['endTime']),
      meetingLocation: J.asString(json['meetingLocation']),
      meetingPlaceType: J.asString(json['meetingPlaceType']),
      hourlyRate: J.asDouble(json['hourlyRate']),
      totalAmount: J.asDouble(json['totalAmount']),
      commissionRate: J.asDouble(json['commissionRate']),
      commissionAmount: J.asDouble(json['commissionAmount']),
      companionPayout: J.asDouble(json['companionPayout']),
      status: J.asString(json['status'], BookingStatus.pending),
      notes: J.asStringOrNull(json['notes']),
      cancellationReason: J.asStringOrNull(json['cancellationReason']),
      completedAt: J.asDate(json['completedAt']),
      createdAt: J.asDate(json['createdAt']),
      companion: json['companion'] is Map
          ? BookingParty.fromJson(J.asMap(json['companion']))
          : null,
      customer: json['customer'] is Map
          ? BookingParty.fromJson(J.asMap(json['customer']))
          : null,
      payment: json['payment'] is Map
          ? PaymentModel.fromJson(J.asMap(json['payment']))
          : null,
      statusHistory: J
          .asMapList(json['statusHistory'])
          .map(BookingStatusEntry.fromJson)
          .toList(growable: false),
      hasReview: json['review'] != null || J.asBool(json['hasReview']),
      startCode: J.asStringOrNull(json['startCode']),
      startedAt: J.asDate(json['startedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingCode': bookingCode,
        'customerId': customerId,
        'companionId': companionId,
        'categoryId': categoryId,
        'activity': activity,
        'durationHours': durationHours,
        'bookingDate': bookingDate?.toIso8601String(),
        'startTime': startTime,
        'endTime': endTime,
        'meetingLocation': meetingLocation,
        'meetingPlaceType': meetingPlaceType,
        'hourlyRate': hourlyRate,
        'totalAmount': totalAmount,
        'commissionRate': commissionRate,
        'commissionAmount': commissionAmount,
        'companionPayout': companionPayout,
        'status': status,
        'notes': notes,
        'cancellationReason': cancellationReason,
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'startCode': startCode,
        'startedAt': startedAt?.toIso8601String(),
      };
}
