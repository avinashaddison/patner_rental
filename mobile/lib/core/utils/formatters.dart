import 'package:intl/intl.dart';

import 'package:companion_ranchi/core/constants/app_constants.dart';

/// Centralised formatting helpers (money in INR, dates, times, relative time).
class Formatters {
  Formatters._();

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '${AppConstants.currencySymbol} ',
    decimalDigits: 0,
  );

  static final NumberFormat _inrDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '${AppConstants.currencySymbol} ',
    decimalDigits: 2,
  );

  /// `₹ 1,200` (no paise). Use [moneyPrecise] when paise matter.
  static String money(num amount) => _inr.format(amount);

  /// `₹ 1,200.50` (two decimals).
  static String moneyPrecise(num amount) => _inrDecimal.format(amount);

  /// `₹ 1,200` when the amount is whole, `₹ 1,200.50` when paise exist —
  /// keeps money displays consistent without ever rounding real paise away.
  static String moneySmart(num amount) {
    final hasPaise = (amount - amount.truncateToDouble()).abs() >= 0.005;
    return hasPaise ? moneyPrecise(amount) : money(amount);
  }

  /// `₹600/hr`.
  static String ratePerHour(num amount) =>
      '${AppConstants.currencySymbol}${amount.toStringAsFixed(0)}/hr';

  /// `Mon, 12 Jun`.
  static String date(DateTime date) => DateFormat('EEE, d MMM').format(date);

  /// `12 June 2026`.
  static String dateLong(DateTime date) =>
      DateFormat('d MMMM y').format(date);

  /// `12 Jun 2026`.
  static String dateShort(DateTime date) =>
      DateFormat('d MMM y').format(date);

  /// `2026-06-12` (API date param).
  static String apiDate(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  /// `3:30 PM` from a "HH:mm" string. Returns the input on parse failure.
  static String time12(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return hhmm;
    final dt = DateTime(2000, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  /// `3:30 PM` from a DateTime. Server timestamps are UTC, so render in the
  /// device's local timezone.
  static String timeOfDay(DateTime dt) =>
      DateFormat('h:mm a').format(dt.toLocal());

  /// `12 Jun, 3:30 PM` (rendered in local time).
  static String dateTime(DateTime dt) =>
      DateFormat('d MMM, h:mm a').format(dt.toLocal());

  /// Compact relative time: `now`, `5m`, `3h`, `2d`, else a short date.
  static String relative(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('d MMM').format(local);
  }

  /// Hours label: `1 hr`, `2 hrs`.
  static String durationHours(int hours) =>
      hours == 1 ? '1 hr' : '$hours hrs';

  /// `2.4 km away`.
  static String distance(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }
}
