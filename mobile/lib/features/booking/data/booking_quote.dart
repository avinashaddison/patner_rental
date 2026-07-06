import 'package:companion_ranchi/core/models/json_utils.dart';

/// Price breakdown returned by `POST /bookings/quote` (no DB write).
///
/// Mirrors the money math in DATA_MODEL.md:
/// ```
/// totalAmount      = hourlyRate * durationHours
/// commissionAmount = round2(totalAmount * commissionRate / 100)
/// companionPayout  = totalAmount - commissionAmount
/// ```
class BookingQuote {
  const BookingQuote({
    required this.hourlyRate,
    required this.durationHours,
    required this.totalAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.companionPayout,
    this.currency = 'INR',
  });

  final double hourlyRate;
  final int durationHours;
  final double totalAmount;
  final double commissionRate;
  final double commissionAmount;
  final double companionPayout;
  final String currency;

  factory BookingQuote.fromJson(Map<String, dynamic> json) => BookingQuote(
        hourlyRate: J.asDouble(json['hourlyRate']),
        durationHours: J.asInt(json['durationHours'], 1),
        totalAmount: J.asDouble(json['totalAmount']),
        commissionRate: J.asDouble(json['commissionRate']),
        commissionAmount: J.asDouble(json['commissionAmount']),
        companionPayout: J.asDouble(json['companionPayout']),
        currency: J.asString(json['currency'], 'INR'),
      );
}

/// One bookable time slot for a given date (`GET /companions/:id/availability`).
/// The backend returns slots that are within the companion's weekly windows and
/// not already booked. Shape is tolerant of either `{ start, end }` or
/// `{ startTime, endTime }` plus an optional `available` flag.
class TimeSlot {
  const TimeSlot({
    required this.startTime,
    required this.endTime,
    this.isAvailable = true,
  });

  /// "HH:mm".
  final String startTime;

  /// "HH:mm".
  final String endTime;
  final bool isAvailable;

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
        startTime: J.asString(json['startTime'] ?? json['start']),
        endTime: J.asString(json['endTime'] ?? json['end']),
        isAvailable: J.asBool(json['isAvailable'] ?? json['available'], true),
      );

  @override
  bool operator ==(Object other) =>
      other is TimeSlot &&
      other.startTime == startTime &&
      other.endTime == endTime;

  @override
  int get hashCode => Object.hash(startTime, endTime);
}
