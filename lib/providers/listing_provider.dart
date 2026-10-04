import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listing_model.dart';
import '../services/firestore_service.dart';

/// Sort for the bidding list (Phase 3.6). All client-side.
enum AuctionSort { newest, endingSoon, mostBids }

/// Listing discovery state: active listings plus client-side search/filter.
///
/// Firestore does one equality-only stream (`status == active`); every
/// filter, sort and page below is applied in Dart because composite
/// indexes are not deployed.
class ListingProvider extends ChangeNotifier {
  ListingProvider({FirestoreService? firestoreService})
      : _firestore = firestoreService ?? FirestoreService();

  final FirestoreService _firestore;

  StreamSubscription<List<ListingModel>>? _sub;

  List<ListingModel> _all = const [];
  bool _loading = true;
  String _query = '';
  String? _category;
  ListingType? _type;

  // Phase 3.2 filters.
  String? _condition;
  double? _minPrice;
  double? _maxPrice;

  // Phase 3.3 "Visit Stall": scope the feed to one seller. Null = everyone.
  String? _sellerId;

  // Phase 3.6 bidding-list sort.
  AuctionSort _auctionSort = AuctionSort.newest;

  // Client-side paging: the feed shows the first [visibleCount] matches and
  // reveals more as the user scrolls (no startAfterDocument — no indexes).
  static const int pageSize = 20;
  int _visibleCount = pageSize;

  bool get isLoading => _loading;
  String get query => _query;
  String? get category => _category;

  /// Feed tab: null = All.
  ListingType? get type => _type;

  String? get condition => _condition;
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;
  String? get sellerId => _sellerId;
  AuctionSort get auctionSort => _auctionSort;

  /// True while any Phase 3.2/3.3 filter is narrowing the feed.
  bool get hasActiveFilters =>
      _category != null ||
      _condition != null ||
      _minPrice != null ||
      _maxPrice != null ||
      _sellerId != null;

  /// Listings after applying type/category/condition/price/seller/search.
  List<ListingModel> get listings {
    var result = _all;
    if (_type != null) {
      result = result.where((l) => l.type == _type).toList();
    }
    if (_sponsorFiltered) {
      result = result.where((l) => l.sellerId == _sellerId).toList();
    }
    if (_category != null && _category!.isNotEmpty) {
      result = result.where((l) => l.category == _category).toList();
    }
    if (_condition != null && _condition!.isNotEmpty) {
      result = result.where((l) => l.condition == _condition).toList();
    }
    if (_minPrice != null) {
      result = result
          .where((l) => (l.displayPrice ?? double.infinity) >= _minPrice!)
          .toList();
    }
    if (_maxPrice != null) {
      result = result
          .where((l) => (l.displayPrice ?? double.negativeInfinity) <=
              _maxPrice!)
          .toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((l) =>
              l.title.toLowerCase().contains(q) ||
              l.description.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  bool get _sponsorFiltered => _sellerId != null && _sellerId!.isNotEmpty;

  /// The current page of [listings].
  List<ListingModel> get visibleListings =>
      listings.take(_visibleCount).toList();

  /// True when more matches exist beyond the current page.
  bool get hasMore => listings.length > _visibleCount;

  /// Live auctions sorted per [_auctionSort] (client-side).
  List<ListingModel> get auctions {
    final now = DateTime.now();
    final open = _all
        .where((l) =>
            l.type == ListingType.bid &&
            l.status == ListingStatus.active &&
            (l.auctionEndAt == null || l.auctionEndAt!.isAfter(now)))
        .toList();
    switch (_auctionSort) {
      case AuctionSort.newest:
        open.sort((a, b) => _compareDates(b.createdAt, a.createdAt));
      case AuctionSort.endingSoon:
        open.sort((a, b) => _compareDates(a.auctionEndAt, b.auctionEndAt));
      case AuctionSort.mostBids:
        open.sort((a, b) => b.bidCount.compareTo(a.bidCount));
    }
    return open;
  }

  static int _compareDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  /// Starts listening to active listings. Call once (e.g. in the home screen).
  void load() {
    _sub?.cancel();
    _loading = true;
    notifyListeners();
    _sub = _firestore.streamActiveListings().listen(
      (listings) {
        _all = listings;
        _loading = false;
        notifyListeners();
      },
      onError: (Object e) {
        _loading = false;
        notifyListeners();
      },
    );
  }

  void _resetPaging() {
    _visibleCount = pageSize;
  }

  /// Reveals the next page. Returns false when everything is visible.
  bool showMore() {
    if (!hasMore) return false;
    _visibleCount += pageSize;
    notifyListeners();
    return true;
  }

  void setCategory(String? category) {
    _category = category;
    _resetPaging();
    notifyListeners();
  }

  void setType(ListingType? type) {
    _type = type;
    _resetPaging();
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    _resetPaging();
    notifyListeners();
  }

  void setCondition(String? condition) {
    _condition = condition;
    _resetPaging();
    notifyListeners();
  }

  void setPriceRange(double? min, double? max) {
    _minPrice = min;
    _maxPrice = max;
    _resetPaging();
    notifyListeners();
  }

  void setSeller(String? sellerId) {
    _sellerId = sellerId;
    _resetPaging();
    notifyListeners();
  }

  void setAuctionSort(AuctionSort sort) {
    _auctionSort = sort;
    notifyListeners();
  }

  /// Clears every Phase 3.2/3.3 filter (keeps the type tab and query).
  void clearFilters() {
    _category = null;
    _condition = null;
    _minPrice = null;
    _maxPrice = null;
    _sellerId = null;
    _resetPaging();
    notifyListeners();
  }

  Future<String> createListing(ListingModel listing) =>
      _firestore.createListing(listing);

  Future<void> refresh() async => load();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
