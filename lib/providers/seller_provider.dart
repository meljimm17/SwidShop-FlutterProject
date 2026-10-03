import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listing_model.dart';
import '../models/swap_offer_model.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';

/// Tabs on My Listings.
enum MyListingTab { active, sold, done, expired }

/// Pure derivations over a seller's data (unit-testable without Firebase).
class SellerStats {
  SellerStats._();

  /// * active  → status active
  /// * done    → sold and its transaction is completed
  /// * sold    → sold, deal not completed yet
  /// * expired → expired (no bids) or delisted
  static MyListingTab tabFor(
    ListingModel listing,
    Map<String, TransactionModel> txnByListing,
  ) {
    switch (listing.status) {
      case ListingStatus.active:
        return MyListingTab.active;
      case ListingStatus.sold:
        return txnByListing[listing.listingId]?.status ==
                TransactionStatus.completed
            ? MyListingTab.done
            : MyListingTab.sold;
      case ListingStatus.expired:
      case ListingStatus.removed:
        return MyListingTab.expired;
    }
  }

  /// Sum of this month's non-cancelled deal amounts (swaps count as 0).
  static double salesThisMonth(
    Iterable<TransactionModel> txns, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    var total = 0.0;
    for (final t in txns) {
      if (t.status == TransactionStatus.cancelled) continue;
      // Pending server timestamp → created just now.
      final created = t.createdAt ?? n;
      if (created.year == n.year && created.month == n.month) {
        total += t.amount;
      }
    }
    return total;
  }

  /// Non-cancelled deals created in [now]'s month, shifted by [monthOffset]
  /// (0 = this month, -1 = last month).
  static List<TransactionModel> dealsInMonth(
    Iterable<TransactionModel> txns, {
    DateTime? now,
    int monthOffset = 0,
  }) {
    final n = now ?? DateTime.now();
    final m = DateTime(n.year, n.month + monthOffset);
    return txns.where((t) {
      if (t.status == TransactionStatus.cancelled) return false;
      final c = t.createdAt ?? n;
      return c.year == m.year && c.month == m.month;
    }).toList();
  }

  /// Whole-percent change from [previous] to [current]; null when there is
  /// no previous baseline (avoids a meaningless "+∞%").
  static int? percentChange(double current, double previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous * 100).round();
  }

  /// Listings created in the last [days] days.
  static int addedWithin(
    Iterable<ListingModel> listings, {
    int days = 7,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final since = n.subtract(Duration(days: days));
    return listings.where((l) => (l.createdAt ?? n).isAfter(since)).length;
  }

  /// Completed (settled) totals for the last [months] months, oldest first.
  static List<({DateTime month, double total})> monthlySettled(
    Iterable<TransactionModel> txns, {
    int months = 6,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    return [
      for (var i = months - 1; i >= 0; i--)
        (
          month: DateTime(n.year, n.month - i),
          total: txns
              .where(
                (t) =>
                    t.status == TransactionStatus.completed &&
                    (t.createdAt ?? n).year ==
                        DateTime(n.year, n.month - i).year &&
                    (t.createdAt ?? n).month ==
                        DateTime(n.year, n.month - i).month,
              )
              .fold<double>(0, (s, t) => s + t.amount),
        ),
    ];
  }

  /// Share of listed items that ended in a deal (sold or done), excluding
  /// delisted ones. Null with nothing to measure.
  static double? sellThrough(Iterable<ListingModel> listings) {
    final counted = listings
        .where((l) => l.status != ListingStatus.removed)
        .toList();
    if (counted.isEmpty) return null;
    final sold = counted.where((l) => l.status == ListingStatus.sold).length;
    return sold / counted.length;
  }

  /// Latest transaction per listing id.
  static Map<String, TransactionModel> txnByListing(
    Iterable<TransactionModel> txns,
  ) {
    final map = <String, TransactionModel>{};
    for (final t in txns) {
      // `txns` is newest-first; keep the first seen.
      map.putIfAbsent(t.listingId, () => t);
    }
    return map;
  }
}

/// Live Seller Centre data for the signed-in user: their listings, swap
/// offers on those listings, and their sales transactions.
///
/// Wired as a proxy of AuthProvider; streams only start when a seller
/// screen calls [start], so pure buyers never pay for these reads.
class SellerProvider extends ChangeNotifier {
  SellerProvider({FirestoreService? firestoreService})
    : _firestoreOverride = firestoreService;

  final FirestoreService? _firestoreOverride;
  FirestoreService? _firestoreLazy;
  FirestoreService get _firestore =>
      _firestoreOverride ?? (_firestoreLazy ??= FirestoreService());

  String? _uid;
  bool _started = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  List<ListingModel> _listings = const [];
  List<SwapOfferModel> _offers = const [];
  List<TransactionModel> _txns = const [];
  bool _listingsLoaded = false;
  bool _offersLoaded = false;
  bool _txnsLoaded = false;
  Object? _error;

  String? get uid => _uid;
  Object? get error => _error;
  bool get isLoading => !(_listingsLoaded && _offersLoaded && _txnsLoaded);

  List<ListingModel> get listings => _listings;
  List<SwapOfferModel> get offers => _offers;
  List<TransactionModel> get transactions => _txns;

  /// Called by the proxy provider whenever auth changes.
  void setUser(String? uid) {
    if (uid == _uid) return;
    final wasStarted = _started;
    _cancel();
    _uid = uid;
    _reset();
    if (wasStarted && uid != null) start();
  }

  /// Begins listening (idempotent).
  void start() {
    final uid = _uid;
    if (uid == null || _started) return;
    _started = true;
    void onError(Object e) {
      debugPrint('SellerProvider stream error: $e');
      _error = e;
      _listingsLoaded = _offersLoaded = _txnsLoaded = true;
      notifyListeners();
    }

    _subs
      ..add(
        _firestore.streamSellerListings(uid).listen((v) {
          _listings = v;
          _listingsLoaded = true;
          notifyListeners();
        }, onError: onError),
      )
      ..add(
        _firestore.streamSellerOffers(uid).listen((v) {
          _offers = v;
          _offersLoaded = true;
          notifyListeners();
        }, onError: onError),
      )
      ..add(
        _firestore.streamSellerTransactions(uid).listen((v) {
          _txns = v;
          _txnsLoaded = true;
          notifyListeners();
        }, onError: onError),
      );
  }

  // --- Derived -------------------------------------------------------------

  ListingModel? listingById(String id) {
    for (final l in _listings) {
      if (l.listingId == id) return l;
    }
    return null;
  }

  List<ListingModel> get activeListings =>
      _listings.where((l) => l.status == ListingStatus.active).toList();

  List<ListingModel> get liveAuctions => _listings
      .where(
        (l) => l.type == ListingType.bid && l.status == ListingStatus.active,
      )
      .toList();

  List<SwapOfferModel> get pendingOffers =>
      _offers.where((o) => o.status == SwapOfferStatus.pending).toList();

  int offerCountFor(String listingId) =>
      _offers.where((o) => o.listingId == listingId).length;

  /// Listings with any bid or swap offer can't be edited or delisted.
  bool isLocked(ListingModel l) => l.hasBids || offerCountFor(l.listingId) > 0;

  Map<String, TransactionModel> get txnByListing =>
      SellerStats.txnByListing(_txns);

  MyListingTab tabFor(ListingModel l) => SellerStats.tabFor(l, txnByListing);

  double get salesThisMonth => SellerStats.salesThisMonth(_txns);

  int get dealsThisMonth => SellerStats.dealsInMonth(_txns).length;

  /// Sales this month vs last month, or null without a baseline.
  int? get salesChangePercent => SellerStats.percentChange(
    salesThisMonth,
    SellerStats.dealsInMonth(
      _txns,
      monthOffset: -1,
    ).fold<double>(0, (s, t) => s + t.amount),
  );

  int get listingsAddedThisWeek => SellerStats.addedWithin(_listings);

  /// Deals still being arranged (shown under Orders).
  List<TransactionModel> get openOrders => _txns
      .where(
        (t) =>
            t.status == TransactionStatus.pending ||
            t.status == TransactionStatus.ongoing ||
            t.status == TransactionStatus.disputed,
      )
      .toList();

  /// Auctions with at least one bid, ending soonest first.
  List<ListingModel> get biddedAuctions =>
      liveAuctions.where((l) => l.hasBids).toList()..sort(
        (a, b) => (a.auctionEndAt ?? DateTime(9999)).compareTo(
          b.auctionEndAt ?? DateTime(9999),
        ),
      );

  List<TransactionModel> get completedSales =>
      _txns.where((t) => t.status == TransactionStatus.completed).toList();

  void _reset() {
    _listings = const [];
    _offers = const [];
    _txns = const [];
    _listingsLoaded = _offersLoaded = _txnsLoaded = false;
    _error = null;
    _started = false;
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
