import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listing_model.dart';
import '../services/firestore_service.dart';

/// Listing discovery state: active listings, category filter, search query.
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

  bool get isLoading => _loading;
  String get query => _query;
  String? get category => _category;

  /// Feed tab: null = All.
  ListingType? get type => _type;

  /// Listings after applying the active category and search query.
  List<ListingModel> get listings {
    var result = _all;
    if (_type != null) {
      result = result.where((l) => l.type == _type).toList();
    }
    if (_category != null && _category!.isNotEmpty) {
      result = result.where((l) => l.category == _category).toList();
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

  void setCategory(String? category) {
    _category = category;
    notifyListeners();
  }

  void setType(ListingType? type) {
    _type = type;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
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
