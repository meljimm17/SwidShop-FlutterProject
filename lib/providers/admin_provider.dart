import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listing_model.dart';
import '../models/partner_ad_model.dart';
import '../models/payment_model.dart';
import '../models/report_model.dart';
import '../models/role_request_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

/// Demo revenue derivations (all simulated money — UI labels them "Demo
/// data"). Payments are the `payments` records; partner-ad revenue is the
/// admin-entered `pricePaid` on each ad.
class RevenueStats {
  RevenueStats._();

  /// Stream keys, in display order.
  static const List<String> streams = [
    PaymentType.fee,
    PaymentType.boost,
    PaymentType.featured,
    PaymentType.plan,
    PaymentType.photoPack,
    'ad',
  ];

  static const Map<String, String> labels = {
    PaymentType.fee: 'Commission fees',
    PaymentType.boost: 'Boosts',
    PaymentType.featured: 'Featured',
    PaymentType.plan: 'Plans',
    PaymentType.photoPack: 'Photo packs',
    'ad': 'Partner ads',
  };

  /// Revenue per stream (every key in [streams] present, zero when none).
  static Map<String, double> byStream(
    Iterable<PaymentModel> payments,
    Iterable<PartnerAdModel> ads,
  ) {
    final out = {for (final k in streams) k: 0.0};
    for (final p in payments) {
      out[p.type] = (out[p.type] ?? 0) + p.amount;
    }
    for (final a in ads) {
      out['ad'] = out['ad']! + a.pricePaid;
    }
    return out;
  }

  static double total(Map<String, double> byStream) =>
      byStream.values.fold(0.0, (a, b) => a + b);

  /// Collected (paid) and outstanding (unpaid) platform fees.
  static ({double collected, double outstanding, double overdue}) fees(
    Iterable<TransactionModel> txns,
  ) {
    var collected = 0.0;
    var outstanding = 0.0;
    var overdue = 0.0;
    for (final t in txns) {
      if (t.feeStatus == 'paid') collected += t.feeAmount;
      if (t.feeUnpaid && t.status != TransactionStatus.cancelled) {
        outstanding += t.feeAmount;
        if (t.feeOverdue) overdue += t.feeAmount;
      }
    }
    return (collected: collected, outstanding: outstanding, overdue: overdue);
  }

  /// Payment revenue per week (Monday start), oldest first, last [weeks].
  /// Ads are excluded (they have no payment date of their own).
  static List<({DateTime week, double total})> weekly(
    Iterable<PaymentModel> payments, {
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
    final totals = List<double>.filled(weeks, 0);
    for (final p in payments) {
      final c = p.createdAt ?? n;
      final day = DateTime(c.year, c.month, c.day);
      final diff = day.difference(first).inDays;
      if (diff < 0) continue;
      final i = diff ~/ 7;
      if (i >= weeks) continue;
      totals[i] += p.amount;
    }
    return [
      for (var i = 0; i < weeks; i++)
        (
          week: DateTime(first.year, first.month, first.day + 7 * i),
          total: totals[i],
        ),
    ];
  }

  /// Sellers on a live paid plan, by plan.
  static ({int plus, int pro}) paidPlans(Iterable<UserModel> users) {
    var plus = 0;
    var pro = 0;
    for (final u in users) {
      switch (u.effectivePlan) {
        case 'plus':
          plus++;
        case 'pro':
          pro++;
      }
    }
    return (plus: plus, pro: pro);
  }

  static int activeBoosts(Iterable<UserModel> users) =>
      users.where((u) => u.isBoosted).length;
}

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
              u.role == UserRole.both &&
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
      _usersLoaded = _listingsLoaded = _txnsLoaded = _reportsLoaded =
          _purchasesLoaded = _adsLoaded = true;
      notifyListeners();
    }

    _subs.addAll([
      _firestore.streamAllUsers().listen((v) {
        _users = v;
        _byUid = {for (final u in v) u.uid: u};
        _usersLoaded = true;
        notifyListeners();
        _migrateLegacySellers(v);
        _reviewTrust(v);
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
      _firestore.streamAllPayments().listen((v) {
        _purchases = v;
        _purchasesLoaded = true;
        notifyListeners();
      }, onError: onError),
      _firestore.streamAllPartnerAds().listen((v) {
        _ads = v;
        _adsLoaded = true;
        notifyListeners();
      }, onError: onError),
      // Optional: a failure here must not blank the rest of the console.
      _firestore.streamAllRoleRequests().listen((v) {
        _roleRequests = v;
        notifyListeners();
      }, onError: (Object e) => debugPrint('roleRequests stream: $e')),
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

  /// Demo payment records (Step 1 flow — no real money).
  List<PaymentModel> _purchases = const [];
  List<PartnerAdModel> _ads = const [];
  List<RoleRequestModel> _roleRequests = const [];

  /// uids already rewritten from the retired 'seller' role this session.
  final Set<String> _migratedRoles = {};

  /// Opening the admin console upgrades every stored seller-only role to
  /// Customer + Seller (the app already treats them that way).
  void _migrateLegacySellers(List<UserModel> users) {
    for (final u in users) {
      if (!u.legacySellerRole || !_migratedRoles.add(u.uid)) continue;
      _firestore
          .migrateLegacySellerRole(u.uid)
          .catchError((Object e) => debugPrint('migrateRole ${u.uid}: $e'));
    }
  }

  bool _trustReviewed = false;

  /// Trusted Seller check for every seller, once per console session. The
  /// trust Cloud Function isn't deployed, so this is what flags newly
  /// eligible sellers (admins get a `trust:{uid}` notification) and strips
  /// badges that no longer qualify. Sequential to keep reads modest.
  Future<void> _reviewTrust(List<UserModel> users) async {
    if (_trustReviewed) return;
    _trustReviewed = true;
    for (final u in users) {
      if (u.role != UserRole.both) continue;
      try {
        await Future.sync(() => _firestore.recomputeTrust(u.uid));
      } catch (e) {
        debugPrint('reviewTrust ${u.uid}: $e');
      }
    }
  }

  bool _usersLoaded = false;
  bool _listingsLoaded = false;
  bool _txnsLoaded = false;
  bool _reportsLoaded = false;
  bool _purchasesLoaded = false;
  bool _adsLoaded = false;
  Object? _error;

  bool get isLoading =>
      !(_usersLoaded &&
          _listingsLoaded &&
          _txnsLoaded &&
          _reportsLoaded &&
          _purchasesLoaded &&
          _adsLoaded);
  Object? get error => _error;

  List<UserModel> get users => _users;
  List<ListingModel> get listings => _listings;
  List<TransactionModel> get transactions => _txns;
  List<ReportModel> get reports => _reports;
  List<PaymentModel> get payments => _purchases;
  List<PartnerAdModel> get partnerAds => _ads;

  /// Role-change requests, pending first.
  List<RoleRequestModel> get roleRequests => _roleRequests;
  int get pendingRoleRequests =>
      _roleRequests.where((r) => r.isPending).length;

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
