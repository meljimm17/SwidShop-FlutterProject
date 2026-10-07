import 'package:intl/intl.dart';

/// Small, dependency-light helpers shared across SwidShop.
class AppUtils {
  AppUtils._();

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final DateFormat _date = DateFormat('MMM d, y');
  static final DateFormat _dateTime = DateFormat('MMM d, y • h:mm a');

  /// Formats a number as Philippine peso, e.g. `₱1,250.00`.
  static String formatCurrency(num? amount) =>
      amount == null ? '—' : _currency.format(amount);

  /// Formats a [DateTime] as `Mar 3, 2026`.
  static String formatDate(DateTime? date) =>
      date == null ? '—' : _date.format(date);

  /// Formats a [DateTime] as `Mar 3, 2026 • 4:20 PM`.
  static String formatDateTime(DateTime? date) =>
      date == null ? '—' : _dateTime.format(date);

  /// Human readable remaining time until [end], e.g. `2d 4h left`.
  static String timeRemaining(DateTime? end) {
    if (end == null) return '—';
    final diff = end.difference(DateTime.now());
    if (diff.isNegative) return 'Ended';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h left';
    if (hours > 0) return '${hours}h ${minutes}m left';
    if (minutes > 0) return '${minutes}m left';
    return '${diff.inSeconds}s left';
  }

  /// Compact length, e.g. `10 min`, `1 h 30 min`, `3 days`, `1 day 6 h`.
  static String formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final parts = <String>[
      if (days > 0) '$days day${days == 1 ? '' : 's'}',
      if (hours > 0) '$hours h',
      if (minutes > 0) '$minutes min',
    ];
    return parts.isEmpty ? '0 min' : parts.join(' ');
  }

  /// Live countdown text, e.g. `2d 04:12:09`, `04:12:09`, or `00:00:00`.
  static String formatCountdown(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final hms =
        '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inDays > 0 ? '${d.inDays}d $hms' : hms;
  }

  /// True when [date] falls in the same calendar month as [now].
  static bool isSameMonth(DateTime? date, {DateTime? now}) {
    if (date == null) return false;
    final n = now ?? DateTime.now();
    return date.year == n.year && date.month == n.month;
  }

  /// True when the auction ends within the next 24 hours.
  static bool isEndingSoon(DateTime? end) {
    if (end == null) return false;
    final diff = end.difference(DateTime.now());
    return !diff.isNegative && diff.inHours < 24;
  }

  /// Converts Firestore `Timestamp`/int/String to [DateTime] safely.
  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    // Firestore Timestamp exposes toDate().
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// Rounds to 1 decimal place, e.g. 4.666 -> 4.7.
  static double roundRating(num value) => (value.toDouble() * 10).round() / 10;
}

/// Reusable form-field validators.
class Validators {
  Validators._();

  static final RegExp _emailRegExp = RegExp(
    r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$',
  );

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegExp.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  /// Sign-up password: at least 8 characters with a letter and a number.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// Philippine mobile number without the +63 prefix, e.g. `917 123 4567`.
  static String? phMobile(String? value) {
    final input = value?.trim() ?? '';
    if (input.isNotEmpty && !RegExp(r'^[\d\s()-]+$').hasMatch(input)) {
      return 'Use digits only';
    }
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Mobile number is required';
    if (digits.length != 10 || !digits.startsWith('9')) {
      return 'Enter a 10-digit number starting with 9';
    }
    return null;
  }

  /// Philippine 4-digit postal code.
  static String? phPostalCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Postal code is required';
    if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'Use the 4-digit postal code';
    return null;
  }

  /// True when [dob] is at least [years] before [now].
  static bool isAtLeastAge(DateTime dob, int years, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final birthday = DateTime(today.year - years, today.month, today.day);
    return !dob.isAfter(birthday);
  }

  static String? required(String? value, [String label = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? positiveNumber(String? value, [String label = 'Amount']) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    final parsed = num.tryParse(value.trim());
    if (parsed == null || !parsed.isFinite) return '$label must be a number';
    if (parsed <= 0) return '$label must be greater than zero';
    return null;
  }

  /// Validates optional minimum / maximum price fields without silently
  /// treating malformed values as an omitted filter.
  static String? priceRange(String? minValue, String? maxValue) {
    final minText = minValue?.trim() ?? '';
    final maxText = maxValue?.trim() ?? '';
    final min = minText.isEmpty ? null : double.tryParse(minText);
    final max = maxText.isEmpty ? null : double.tryParse(maxText);
    if (minText.isNotEmpty && (min == null || !min.isFinite)) {
      return 'Minimum price must be a valid number';
    }
    if (maxText.isNotEmpty && (max == null || !max.isFinite)) {
      return 'Maximum price must be a valid number';
    }
    if (min != null && min < 0 || max != null && max < 0) {
      return 'Prices cannot be negative';
    }
    if (min != null && max != null && min > max) {
      return 'Minimum price cannot be greater than maximum price';
    }
    return null;
  }
}
