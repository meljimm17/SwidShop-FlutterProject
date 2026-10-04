import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listing_model.dart';
import '../models/report_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

/// Pure derivations over the whole marketplace (unit-testable without
/// Firebase). Every admin number comes from here — nothing is invented.
class AdminStats {
  AdminStats._();

  static Map<UserRole, int> roleCounts(Iterable<UserModel> users) {
    final counts = {for (final r in UserRole.values) r: 0};
    for (final u in users) {
      counts[u.role] = counts[u.role]! + 1;
    }
    return counts;
  }

  /// Listing counts per type among [listings].
  static Map<ListingType, int> typeCounts(Iterable<ListingModel> listings) {
    final counts = {for (final t in ListingType.values) t: 0};
    for (final l in listings) {
      counts[l.type] = counts[l.type]! + 1;
    }
    return counts;
  }

  /// Deals created per week (Monday start) for the last [weeks] weeks,
  /// oldest first, split by listing type. Cancelled deals are skipped.
  static List<({DateTime week, int buyNow, int bid, int swap})> weeklyDeals(
    Iterable<TransactionModel> txns, {
    int weeks = 6,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final first = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - 7 * (weeks - 1),
    );
    final counts = List.generate(weeks, (_) => [0, 0, 0]);
    for (final t in txns) {
      if (t.status == TransactionStatus.cancelled) continue;
      final c = t.createdAt ?? n;
      final day = DateTime(c.year, c.month, c.day);
      final diff = day.difference(first).inDays;
      if (diff < 0) continue;
      final i = diff ~/ 7;
      if (i >= weeks) continue;
      counts[i][t.type.index]++;
    }
    return [
      for (var i = 0; i < weeks; i++)
        (
          week: DateTime(first.year, first.month, first.day + 7 * i),
          buyNow: counts[i][ListingType.buyNow.index],
          bid: counts[i][ListingType.bid.index],
          swap: counts[i][ListingType.swap.index],
        ),
    ];
  }

  /// Total registered users at the end of each of the last [months]
  /// months, oldest first (docs without createdAt count from the start).
  static List<({DateTime month, int total})> userGrowth(
    Iterable<UserModel> users, {
    int months = 6,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    return [
      for (var i = months - 1; i >= 0; i--)
        (
          month: DateTime(n.year, n.month - i),
          total: users.where((u) {
            final c = u.createdAt;
            if (c == null) return true;
            final endOfMonth = DateTime(n.year, n.month - i + 1);
            return c.isBefore(endOfMonth);
          }).length,
        ),
    ];
  }

  /// Whole-percent change; null without a baseline.
  static int? percentChange(num current, num previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous * 100).round();
  }

  /// Sum of completed cash deals (swaps carry no money).
  static double settledVolume(Iterable<TransactionModel> txns) => txns
      .where(
        (t) =>
            t.status == TransactionStatus.completed &&
            t.type != ListingType.swap,
      )
      .fold<double>(0, (s, t) => s + t.amount);

  /// Completed deals created in the month [monthOffset] away from [now].
  static int completedInMonth(
    Iterable<TransactionModel> txns, {
    int monthOffset = 0,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final m = DateTime(n.year, n.month + monthOffset);
    return txns.where((t) {
      if (t.status != TransactionStatus.completed) return false;
      final c = t.createdAt ?? n;
      return c.year == m.year && c.month == m.month;
    }).length;
  }

  /// Completed ÷ (completed + cancelled + disputed) as 0–100; null if none.
  static int? cleanRate(Iterable<TransactionModel> txns) {
    var completed = 0;
    var resolved = 0;
    for (final t in txns) {
      switch (t.status) {
        case TransactionStatus.completed:
          completed++;
          resolved++;
        case TransactionStatus.cancelled:
        case TransactionStatus.disputed:
          resolved++;
        case TransactionStatus.pending:
        case TransactionStatus.ongoing:
          break;
      }
    }
    return resolved == 0 ? null : (completed / resolved * 100).round();
  }

  /// Ids of targets of [type] with at least one pending report.
  static Set<String> flaggedIds(
    Iterable<ReportModel> reports,
    ReportTargetType type,
  ) => {
    for (final r in reports)
      if (r.status == ReportStatus.pending && r.targetType == type) r.targetId,
  };

  /// Pending reports against [targetId].
  static int pendingFor(Iterable<ReportModel> reports, String targetId) =>
      reports
          .where(
            (r) => r.targetId == targetId && r.status == ReportStatus.pending,
          )
          .length;

  /// Upheld reports against [targetId] (warned / suspended / removed).
  static int strikesFor(Iterable<ReportModel> reports, String targetId) =>
      reports
          .where(
            (r) =>
                r.targetId == targetId &&
                (r.status == ReportStatus.warned ||
                    r.status == ReportStatus.suspended ||
                    r.status == ReportStatus.removed),
          )
          .length;

  /// Sellers worth a look: trusted first, then rating, then deal count.
  /// Only accounts with at least one completed deal or the Trusted badge.
  static List<UserModel> topSellers(Iterable<UserModel> users, {int max = 8}) {
    final sellers = users
        .where(
          (u) =>
              (u.role == UserRole.seller || u.role == UserRole.both) &&
              u.accountStatus == AccountStatus.active &&
              (u.trustedBadge || u.completedTransactions > 0),
        )
        .toList();
    sellers.sort((a, b) {
      if (a.trustedBadge != b.trustedBadge) return a.trustedBadge ? -1 : 1;
      final r = b.avgRating.compareTo(a.avgRating);
      if (r != 0) return r;
      return b.completedTransactions.compareTo(a.completedTransactions);
    });
    return sellers.take(max).toList();
  }

  /// Short display code from a Firestore id, e.g. `#RP-9F2A` (real id tail).
  static String shortCode(String prefix, String id, {int length = 4}) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = clean.length > length
        ? clean.substring(clean.length - length)
        : clean;
    return '#$prefix-${tail.toUpperCase()}';
  }
}

/// Live admin data shared by every admin tab: all users, listings,
/// transactions and reports (streams, client-side filtering only).
///
/// Created by `AdminShell`; inject a fake [FirestoreService] in tests.
class AdminProvider extends ChangeNotifier {
  AdminProvider({FirestoreService? firestoreService})
    : _firestore = firestoreService ?? FirestoreService() {
    void onError(Object e) {
      debugPrint('AdminProvider stream error: $e');
      _error = e;
      _usersLoaded = _listingsLoaded = _txnsLoaded = _reportsLoaded = true;
      notifyListeners();
    }

    _subs.addAll([
      _firestore.streamAllUsers().listen((v) {
        _users = v;
        _byUid = {for (final u in v) u.uid: u};
        _usersLoaded = true;
        notifyListeners();
      }, onError: onError),
      _firestore.streamAllListings().listen((v) {
        _listings = v;
        _listingsLoaded = true;
        notifyListeners();
      }, onError: onError),
      _firestore.streamAllTransactions().listen((v) {
        _txns = v;
        _txnsLoaded = true;
        notifyListeners();
      }, onError: onError),
      _firestore.streamAllReports().listen((v) {
        _reports = v;
        _reportsLoaded = true;
        notifyListeners();
      }, onError: onError),
    ]);
  }

  final FirestoreService _firestore;
  final List<StreamSubscription<dynamic>> _subs = [];

  FirestoreService get firestore => _firestore;

  List<UserModel> _users = const [];
  Map<String, UserModel> _byUid = const {};
  List<ListingModel> _listings = const [];
  List<TransactionModel> _txns = const [];
  List<ReportModel> _reports = const [];
  bool _usersLoaded = false;
  bool _listingsLoaded = false;
  bool _txnsLoaded = false;
  bool _reportsLoaded = false;
  Object? _error;

  bool get isLoading =>
      !(_usersLoaded && _listingsLoaded && _txnsLoaded && _reportsLoaded);
  Object? get error => _error;

  List<UserModel> get users => _users;
  List<ListingModel> get listings => _listings;
  List<TransactionModel> get transactions => _txns;
  List<ReportModel> get reports => _reports;

  UserModel? user(String uid) => _byUid[uid];

  /// Display name for a uid, falling back to a neutral label.
  String nameOf(String uid) {
    final u = _byUid[uid];
    if (u == null) return 'Unknown user';
    return u.name.isEmpty ? u.email : u.name;
  }

  List<ReportModel> get pendingReports =>
      _reports.where((r) => r.status == ReportStatus.pending).toList();

  /// Pending user + listing reports (the Reports tab badge / bell count).
  int get pendingQueueCount => pendingReports
      .where((r) => r.targetType != ReportTargetType.rating)
      .length;

  int get pendingRatingFlags => pendingReports
      .where((r) => r.targetType == ReportTargetType.rating)
      .length;

  Set<String> get flaggedListingIds =>
      AdminStats.flaggedIds(_reports, ReportTargetType.listing);

  Set<String> get flaggedUserIds =>
      AdminStats.flaggedIds(_reports, ReportTargetType.user);

  ListingModel? listing(String id) {
    for (final l in _listings) {
      if (l.listingId == id) return l;
    }
    return null;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
