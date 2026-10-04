import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../models/bid_model.dart';
import '../models/category_model.dart';
import '../models/chat_message_model.dart';
import '../models/listing_model.dart';
import '../models/notification_model.dart';
import '../models/rating_model.dart';
import '../models/report_model.dart';
import '../models/swap_offer_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../models/user_private_details_model.dart';

/// Thin, typed data-access layer over Cloud Firestore.
///
/// Every collection/subcollection name comes from [AppConstants] so the
/// schema strings live in exactly one place.
///
/// Queries use equality filters only and sort client-side, so they work
/// without deploying composite indexes (see AGENTS.md).
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(AppConstants.usersCollection);
  CollectionReference<Map<String, dynamic>> get _listings =>
      _db.collection(AppConstants.listingsCollection);
  CollectionReference<Map<String, dynamic>> get _bids =>
      _db.collection(AppConstants.bidsCollection);
  CollectionReference<Map<String, dynamic>> get _swapOffers =>
      _db.collection(AppConstants.swapOffersCollection);
  CollectionReference<Map<String, dynamic>> get _transactions =>
      _db.collection(AppConstants.transactionsCollection);
  CollectionReference<Map<String, dynamic>> get _ratings =>
      _db.collection(AppConstants.ratingsCollection);
  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(AppConstants.reportsCollection);
  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection(AppConstants.categoriesCollection);

  // ---------------------------------------------------------------------------
  // users
  // ---------------------------------------------------------------------------

  Future<void> createUserProfile(UserModel user) =>
      _users.doc(user.uid).set(user.toMap());

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) =>
      _users.doc(uid).update(data);

  Future<UserModel?> getUser(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    return data == null ? null : UserModel.fromMap(snap.id, data);
  }

  static final Map<String, Future<UserModel?>> _userCache = {};

  /// Cached one-shot profile lookup for showing other users' names/ratings
  /// in lists (bid logs, offers, sales rows).
  Future<UserModel?> getUserCached(String uid) =>
      _userCache.putIfAbsent(uid, () => getUser(uid));

  Stream<UserModel?> streamUser(String uid) =>
      _users.doc(uid).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : UserModel.fromMap(snap.id, data);
      });

  DocumentReference<Map<String, dynamic>> _privateDetails(String uid) =>
      _users
          .doc(uid)
          .collection(AppConstants.userPrivateSubcollection)
          .doc(AppConstants.userPrivateDetailsDoc);

  /// Owner/admin-only details (phone, street, ID photos, terms acceptance).
  Future<void> saveUserPrivateDetails(String uid, UserPrivateDetails details) =>
      _privateDetails(uid).set(details.toMap(), SetOptions(merge: true));

  Future<UserPrivateDetails?> getUserPrivateDetails(String uid) async {
    final snap = await _privateDetails(uid).get();
    final data = snap.data();
    return data == null ? null : UserPrivateDetails.fromMap(data);
  }

  // ---------------------------------------------------------------------------
  // listings
  // ---------------------------------------------------------------------------

  /// Reserves a listing id so photos can upload to `listings/{id}` before
  /// the document exists.
  String newListingId() => _listings.doc().id;

  Future<String> createListing(ListingModel listing) async {
    final ref = listing.listingId.isEmpty
        ? _listings.doc()
        : _listings.doc(listing.listingId);
    final data = listing.copyWith(listingId: ref.id).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateListing(String listingId, Map<String, dynamic> data) =>
      _listings.doc(listingId).update(data);

  Future<void> deleteListing(String listingId) =>
      _listings.doc(listingId).delete();

  Future<ListingModel?> getListing(String listingId) async {
    final snap = await _listings.doc(listingId).get();
    final data = snap.data();
    return data == null ? null : ListingModel.fromMap(snap.id, data);
  }

  Stream<ListingModel?> streamListing(String listingId) =>
      _listings.doc(listingId).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : ListingModel.fromMap(snap.id, data);
      });

  /// Newest first. `createdAt` is null for a moment after a local write
  /// (server timestamp pending) — treat that as "just now".
  static int _newestFirst(DateTime? a, DateTime? b) =>
      (b ?? DateTime.now()).compareTo(a ?? DateTime.now());

  Stream<List<ListingModel>> streamActiveListings({
    String? category,
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query =
        _listings.where('status', isEqualTo: ListingStatus.active.value);
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }
    return query.limit(limit).snapshots().map((snap) {
      final items =
          snap.docs.map((d) => ListingModel.fromMap(d.id, d.data())).toList();
      items.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
      return items;
    });
  }

  /// All of a seller's listings (every status), newest first.
  Stream<List<ListingModel>> streamSellerListings(String sellerId) => _listings
          .where('sellerId', isEqualTo: sellerId)
          .snapshots()
          .map((snap) {
        final items =
            snap.docs.map((d) => ListingModel.fromMap(d.id, d.data())).toList();
        items.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
        return items;
      });

  // ---------------------------------------------------------------------------
  // bids
  // ---------------------------------------------------------------------------

  /// Atomically records a bid and updates the listing's highest bid.
  Future<String> placeBid({
    required String listingId,
    required String bidderId,
    required double amount,
  }) async {
    final bidRef = _bids.doc();
    final listingRef = _listings.doc(listingId);

    await _db.runTransaction((tx) async {
      final listingSnap = await tx.get(listingRef);
      final data = listingSnap.data();
      if (data == null) {
        throw StateError('Listing no longer exists.');
      }
      final current = (data['currentHighestBid'] as num?)?.toDouble() ??
          (data['startingBid'] as num?)?.toDouble() ??
          0;
      if ((data['sellerId'] as String? ?? '') == bidderId) {
        throw StateError('You cannot bid on your own listing.');
      }
      if (amount <= current) {
        throw StateError('Bid must be higher than the current highest bid.');
      }
      tx.set(bidRef, {
        'bidId': bidRef.id,
        'listingId': listingId,
        'bidderId': bidderId,
        'amount': amount,
        'placedAt': FieldValue.serverTimestamp(),
      });
      tx.update(listingRef, {
        'currentHighestBid': amount,
        'highestBidderId': bidderId,
        'bidCount': FieldValue.increment(1),
      });
    });

    return bidRef.id;
  }

  /// Bids on a listing, highest amount first (re-sort by `placedAt` for a
  /// chronological log).
  Stream<List<BidModel>> streamBids(String listingId) => _bids
          .where('listingId', isEqualTo: listingId)
          .snapshots()
          .map((snap) {
        final bids =
            snap.docs.map((d) => BidModel.fromMap(d.id, d.data())).toList();
        bids.sort((a, b) => b.amount.compareTo(a.amount));
        return bids;
      });

  /// Closes an auction whose `auctionEndAt` has passed: marks the listing
  /// `sold` (or `expired` with no bids) and creates the winning transaction.
  ///
  /// Idempotent and safe to race with the `closeAuctions` Cloud Function:
  /// the transaction id is fixed (`auction_{listingId}`) and the listing
  /// status is re-checked inside a Firestore transaction. Returns the
  /// transaction id when there is a winner, otherwise null.
  Future<String?> closeAuctionIfEnded(String listingId) async {
    final listingRef = _listings.doc(listingId);
    final txnRef = _transactions.doc('auction_$listingId');
    final bidSnap = await _bids.where('listingId', isEqualTo: listingId).get();
    BidModel? top;
    for (final d in bidSnap.docs) {
      final bid = BidModel.fromMap(d.id, d.data());
      if (top == null || bid.amount > top.amount) top = bid;
    }

    return _db.runTransaction<String?>((tx) async {
      final snap = await tx.get(listingRef);
      final data = snap.data();
      if (data == null) return null;
      final listing = ListingModel.fromMap(snap.id, data);
      if (listing.status != ListingStatus.active) return null;
      final end = listing.auctionEndAt;
      if (end == null || end.isAfter(DateTime.now())) return null;

      // No bids, or the hidden reserve wasn't met → ends unsold.
      final reserve = listing.reservePrice;
      if (top == null || (reserve != null && top.amount < reserve)) {
        tx.update(listingRef, {'status': ListingStatus.expired.value});
        return null;
      }
      tx.update(listingRef, {
        'status': ListingStatus.sold.value,
        'currentHighestBid': top.amount,
      });
      final txn = TransactionModel(
        transactionId: txnRef.id,
        listingId: listingId,
        buyerId: top.bidderId,
        sellerId: listing.sellerId,
        type: ListingType.bid,
        amount: top.amount,
        listingTitle: listing.title,
        listingImage: listing.images.isNotEmpty ? listing.images.first : '',
      ).toMap();
      txn['createdAt'] = FieldValue.serverTimestamp();
      tx.set(txnRef, txn);
      return txnRef.id;
    });
  }

  // ---------------------------------------------------------------------------
  // swapOffers
  // ---------------------------------------------------------------------------

  /// Creates a pending offer. Fills `sellerId` from the target listing when
  /// not provided (rules require it to match the listing owner).
  Future<String> createSwapOffer(SwapOfferModel offer) async {
    final ref = _swapOffers.doc();
    var sellerId = offer.sellerId;
    if (sellerId.isEmpty) {
      sellerId = (await getListing(offer.listingId))?.sellerId ?? '';
    }
    if (sellerId.isNotEmpty && sellerId == offer.offeredById) {
      throw StateError('You cannot swap with your own listing.');
    }
    final data =
        offer.copyWith(offerId: ref.id, sellerId: sellerId).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateSwapOfferStatus(
    String offerId,
    SwapOfferStatus status,
  ) =>
      _swapOffers.doc(offerId).update({'status': status.value});

  /// Every swap offer made on a seller's listings (all statuses), newest
  /// first. Filter `status == pending` client-side for the inbox.
  Stream<List<SwapOfferModel>> streamSellerOffers(String sellerId) =>
      _swapOffers.where('sellerId', isEqualTo: sellerId).snapshots().map((snap) {
        final offers = snap.docs
            .map((d) => SwapOfferModel.fromMap(d.id, d.data()))
            .toList();
        offers.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
        return offers;
      });

  /// Accepts [offer]: offer → accepted, every other pending offer on the
  /// same listing → declined, listing → sold, and a `swap` transaction is
  /// created (id `swap_{offerId}`) whose chat opens the conversation.
  /// Returns the transaction id.
  Future<String> acceptSwapOffer(SwapOfferModel offer) async {
    final listingRef = _listings.doc(offer.listingId);
    final offerRef = _swapOffers.doc(offer.offerId);
    final txnRef = _transactions.doc('swap_${offer.offerId}');
    final pending = await _swapOffers
        .where('listingId', isEqualTo: offer.listingId)
        .where('status', isEqualTo: SwapOfferStatus.pending.value)
        .get();
    final offeredItem = offer.offeredItemId.isEmpty
        ? null
        : await getListing(offer.offeredItemId);

    await _db.runTransaction((tx) async {
      final listingSnap = await tx.get(listingRef);
      final offerSnap = await tx.get(offerRef);
      final listingData = listingSnap.data();
      final offerData = offerSnap.data();
      if (listingData == null || offerData == null) {
        throw StateError('This listing or offer no longer exists.');
      }
      final listing = ListingModel.fromMap(listingSnap.id, listingData);
      if (listing.status != ListingStatus.active) {
        throw StateError('This listing is no longer active.');
      }
      if (SwapOfferModel.fromMap(offerSnap.id, offerData).status !=
          SwapOfferStatus.pending) {
        throw StateError('This offer was already answered.');
      }

      tx.update(offerRef, {'status': SwapOfferStatus.accepted.value});
      for (final d in pending.docs) {
        if (d.id == offer.offerId) continue;
        tx.update(d.reference, {'status': SwapOfferStatus.declined.value});
      }
      tx.update(listingRef, {'status': ListingStatus.sold.value});
      final txn = TransactionModel(
        transactionId: txnRef.id,
        listingId: listing.listingId,
        buyerId: offer.offeredById,
        sellerId: listing.sellerId,
        type: ListingType.swap,
        listingTitle: listing.title,
        listingImage: listing.images.isNotEmpty ? listing.images.first : '',
        offerId: offer.offerId,
        swapItemTitle: offeredItem?.title ?? '',
      ).toMap();
      txn['createdAt'] = FieldValue.serverTimestamp();
      tx.set(txnRef, txn);
    });
    return txnRef.id;
  }

  Stream<List<SwapOfferModel>> streamOffersForListing(String listingId) =>
      _swapOffers.where('listingId', isEqualTo: listingId).snapshots().map(
            (snap) => snap.docs
                .map((d) => SwapOfferModel.fromMap(d.id, d.data()))
                .toList(),
          );

  // ---------------------------------------------------------------------------
  // transactions
  // ---------------------------------------------------------------------------

  Future<String> createTransaction(TransactionModel txn) async {
    final ref = _transactions.doc();
    final data = txn.copyWith(transactionId: ref.id).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateTransactionStatus(
    String transactionId,
    TransactionStatus status,
  ) =>
      _transactions.doc(transactionId).update({'status': status.value});

  /// All of a seller's transactions, newest first.
  Stream<List<TransactionModel>> streamSellerTransactions(String sellerId) =>
      _transactions
          .where('sellerId', isEqualTo: sellerId)
          .snapshots()
          .map((snap) {
        final items = snap.docs
            .map((d) => TransactionModel.fromMap(d.id, d.data()))
            .toList();
        items.sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
        return items;
      });

  Stream<TransactionModel?> streamTransaction(String transactionId) =>
      _transactions.doc(transactionId).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : TransactionModel.fromMap(snap.id, data);
      });

  /// The seller's transaction for [listingId], if one exists (e.g. created
  /// by the auction-closing Cloud Function with a random id).
  Future<TransactionModel?> findSellerTransactionForListing({
    required String sellerId,
    required String listingId,
  }) async {
    final snap = await _transactions
        .where('sellerId', isEqualTo: sellerId)
        .where('listingId', isEqualTo: listingId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return TransactionModel.fromMap(d.id, d.data());
  }

  Stream<List<TransactionModel>> streamTransactionsForUser(String uid) =>
      _transactions
          .where(Filter.or(
            Filter('buyerId', isEqualTo: uid),
            Filter('sellerId', isEqualTo: uid),
          ))
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => TransactionModel.fromMap(d.id, d.data()))
              .toList());

  // ---------------------------------------------------------------------------
  // chats/{transactionId}/messages
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _messages(String transactionId) =>
      _db
          .collection(AppConstants.chatsCollection)
          .doc(transactionId)
          .collection(AppConstants.messagesSubcollection);

  Future<void> sendMessage(
    String transactionId,
    ChatMessageModel message,
  ) async {
    await _messages(transactionId).add({
      'senderId': message.senderId,
      'text': message.text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ChatMessageModel>> streamMessages(String transactionId) =>
      _messages(transactionId)
          .orderBy('timestamp')
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => ChatMessageModel.fromMap(d.id, d.data()))
              .toList());

  // ---------------------------------------------------------------------------
  // ratings
  // ---------------------------------------------------------------------------

  Future<String> addRating(RatingModel rating) async {
    final ref = _ratings.doc();
    final data = rating.copyWith(ratingId: ref.id).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  Stream<List<RatingModel>> streamRatingsForUser(String uid) => _ratings
      .where('ratedUserId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => RatingModel.fromMap(d.id, d.data())).toList());

  // ---------------------------------------------------------------------------
  // reports
  // ---------------------------------------------------------------------------

  Future<String> createReport(ReportModel report) async {
    final ref = _reports.doc();
    final data = report.copyWith(reportId: ref.id).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  // ---------------------------------------------------------------------------
  // categories
  // ---------------------------------------------------------------------------

  Future<void> seedCategories(List<CategoryModel> categories) async {
    final batch = _db.batch();
    for (final c in categories) {
      final ref =
          c.categoryId.isEmpty ? _categories.doc() : _categories.doc(c.categoryId);
      batch.set(ref, c.copyWith(categoryId: ref.id).toMap());
    }
    await batch.commit();
  }

  Stream<List<CategoryModel>> streamCategories() => _categories
      .orderBy('sortOrder')
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => CategoryModel.fromMap(d.id, d.data())).toList());

  // ---------------------------------------------------------------------------
  // notifications/{uid}/items
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _notificationItems(String uid) =>
      _db
          .collection(AppConstants.notificationsCollection)
          .doc(uid)
          .collection(AppConstants.notificationsItemsSubcollection);

  Future<void> addNotification(String uid, NotificationModel n) async {
    await _notificationItems(uid).add({
      'type': n.type.value,
      'message': n.message,
      'relatedId': n.relatedId,
      'read': n.read,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<NotificationModel>> streamNotifications(String uid) =>
      _notificationItems(uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => NotificationModel.fromMap(d.id, d.data()))
              .toList());

  Future<void> markNotificationRead(String uid, String notificationId) =>
      _notificationItems(uid).doc(notificationId).update({'read': true});

  /// Marks every unread item read. Equality-only fetch, batched writes.
  Future<void> markAllNotificationsRead(String uid) async {
    final snap =
        await _notificationItems(uid).where('read', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // buyer-side queries (Phase 3): equality-only, sorted client-side
  // ---------------------------------------------------------------------------

  /// Users holding the Trusted badge, newest-rating first (client sort).
  Stream<List<UserModel>> streamTrustedUsers() => _users
      .where('trustedBadge', isEqualTo: true)
      .snapshots()
      .map((snap) {
    final users =
        snap.docs.map((d) => UserModel.fromMap(d.id, d.data())).toList();
    users.sort((a, b) => b.avgRating.compareTo(a.avgRating));
    return users;
  });

  /// Bids placed by [uid], newest first (client sort).
  Stream<List<BidModel>> streamBidsForBidder(String uid) =>
      _bids.where('bidderId', isEqualTo: uid).snapshots().map((snap) {
        final bids =
            snap.docs.map((d) => BidModel.fromMap(d.id, d.data())).toList();
        bids.sort((a, b) => _compareNullableDates(b.placedAt, a.placedAt));
        return bids;
      });

  /// Swap offers made by [uid], newest first (client sort).
  Stream<List<SwapOfferModel>> streamOffersByUser(String uid) =>
      _swapOffers.where('offeredById', isEqualTo: uid).snapshots().map((snap) {
        final offers = snap.docs
            .map((d) => SwapOfferModel.fromMap(d.id, d.data()))
            .toList();
        offers.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return offers;
      });

  /// Transactions where [uid] is the buyer, newest first (client sort).
  /// (Deliberately buyer-only: the OR+orderBy variant needs an index.)
  Stream<List<TransactionModel>> streamBuyerTransactions(String uid) =>
      _transactions.where('buyerId', isEqualTo: uid).snapshots().map((snap) {
        final txns = snap.docs
            .map((d) => TransactionModel.fromMap(d.id, d.data()))
            .toList();
        txns.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return txns;
      });

  /// Ratings left for one transaction (used to show "Rate" exactly once).
  Future<List<RatingModel>> ratingsForTransaction(String transactionId) async {
    final snap = await _ratings
        .where('transactionId', isEqualTo: transactionId)
        .get();
    return snap.docs.map((d) => RatingModel.fromMap(d.id, d.data())).toList();
  }

  /// Recomputes a user's average rating from their `ratings` docs.
  ///
  /// Client-side stand-in for the `computeTrustBadge` Cloud Function
  /// (not deployed): call after `addRating` so profiles reflect new
  /// reviews immediately.
  Future<void> refreshUserRating(String uid) async {
    final snap = await _ratings.where('ratedUserId', isEqualTo: uid).get();
    var sum = 0.0;
    for (final d in snap.docs) {
      sum += ((d.data()['stars'] as num?) ?? 0).toDouble();
    }
    final avg =
        snap.docs.isEmpty ? 0.0 : (sum / snap.docs.length * 10).round() / 10;
    await _users.doc(uid).update({'avgRating': avg});
  }

  static int _compareNullableDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  // ---------------------------------------------------------------------------
  // Buy Now (Phase 3.5): no money moves in-app — the chat arranges
  // payment/delivery afterwards. Marks the listing sold, records the deal,
  // opens the thread parent doc and notifies the seller.
  // ---------------------------------------------------------------------------

  /// Completes a fixed-price purchase. Returns the new transaction id.
  Future<String> buyNowPurchase({
    required String listingId,
    required String buyerId,
  }) async {
    final listingRef = _listings.doc(listingId);
    final txnRef = _transactions.doc();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(listingRef);
      final data = snap.data();
      if (data == null) throw StateError('Listing no longer exists.');
      if (data['status'] != ListingStatus.active.value) {
        throw StateError('This item is no longer available.');
      }
      if (data['type'] != ListingType.buyNow.value) {
        throw StateError('This item is not a Buy Now listing.');
      }
      if ((data['sellerId'] as String? ?? '') == buyerId) {
        throw StateError('You cannot buy your own listing.');
      }
      tx.update(listingRef, {'status': ListingStatus.sold.value});
      tx.set(txnRef, {
        'transactionId': txnRef.id,
        'listingId': listingId,
        'buyerId': buyerId,
        'sellerId': data['sellerId'],
        'type': ListingType.buyNow.value,
        'amount': data['price'],
        'listingTitle': data['title'] ?? '',
        'listingImage': (data['images'] as List?)?.firstOrNull ?? '',
        'status': TransactionStatus.pending.value,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final listing = await getListing(listingId);
    await ensureChatThread(
      transactionId: txnRef.id,
      buyerId: buyerId,
      sellerId: listing?.sellerId ?? '',
      listingId: listingId,
    );
    if (listing != null && listing.sellerId.isNotEmpty) {
      await addNotification(
        listing.sellerId,
        NotificationModel(
          type: NotificationType.transactionUpdate,
          message: 'Your item "${listing.title}" just sold.',
          relatedId: 'transaction:${txnRef.id}',
        ),
      );
    }
    return txnRef.id;
  }

  /// Creates the `chats/{transactionId}` parent doc (messages live in its
  /// `messages` subcollection) so threads are listable later.
  Future<void> ensureChatThread({
    required String transactionId,
    required String buyerId,
    required String sellerId,
    required String listingId,
  }) =>
      _db.collection(AppConstants.chatsCollection).doc(transactionId).set({
        'transactionId': transactionId,
        'buyerId': buyerId,
        'sellerId': sellerId,
        'listingId': listingId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ---------------------------------------------------------------------------
  // admin (Phase 4): whole-collection streams, client-side sort/filter.
  // No where/orderBy combos — nothing here needs a composite index.
  // ---------------------------------------------------------------------------

  /// Every user doc, newest first (client sort).
  Stream<List<UserModel>> streamAllUsers() =>
      _users.snapshots().map((snap) {
        final users =
            snap.docs.map((d) => UserModel.fromMap(d.id, d.data())).toList();
        users.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return users;
      });

  /// Every listing regardless of status, newest first (client sort).
  Stream<List<ListingModel>> streamAllListings() =>
      _listings.snapshots().map((snap) {
        final items = snap.docs
            .map((d) => ListingModel.fromMap(d.id, d.data()))
            .toList();
        items.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return items;
      });

  /// Every transaction, newest first (client sort).
  Stream<List<TransactionModel>> streamAllTransactions() =>
      _transactions.snapshots().map((snap) {
        final txns = snap.docs
            .map((d) => TransactionModel.fromMap(d.id, d.data()))
            .toList();
        txns.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return txns;
      });

  /// Listings in one category (admin counts, reassign on delete).
  Stream<List<ListingModel>> streamListingsByCategory(String category) =>
      _listings.where('category', isEqualTo: category).snapshots().map((snap) =>
          snap.docs.map((d) => ListingModel.fromMap(d.id, d.data())).toList());

  /// Reports with one status, oldest first (pending urgency).
  Stream<List<ReportModel>> streamReportsByStatus(ReportStatus status) =>
      _reports.where('status', isEqualTo: status.value).snapshots().map((snap) {
        final reports = snap.docs
            .map((d) => ReportModel.fromMap(d.id, d.data()))
            .toList();
        reports
            .sort((a, b) => _compareNullableDates(a.createdAt, b.createdAt));
        return reports;
      });

  /// Every report regardless of status, newest first (client sort).
  Stream<List<ReportModel>> streamAllReports() =>
      _reports.snapshots().map((snap) {
        final reports = snap.docs
            .map((d) => ReportModel.fromMap(d.id, d.data()))
            .toList();
        reports
            .sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return reports;
      });

  /// Rewrites `sortOrder` for every category in the given order (one batch).
  Future<void> reorderCategories(List<String> categoryIdsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < categoryIdsInOrder.length; i++) {
      batch.update(_categories.doc(categoryIdsInOrder[i]), {'sortOrder': i});
    }
    await batch.commit();
  }

  /// Every report ever filed against one target (prior-strikes context).
  Future<List<ReportModel>> reportsForTarget(String targetId) async {
    final snap =
        await _reports.where('targetId', isEqualTo: targetId).get();
    return snap.docs.map((d) => ReportModel.fromMap(d.id, d.data())).toList();
  }

  Future<void> updateReportStatus(
    String reportId,
    ReportStatus status,
  ) =>
      _reports.doc(reportId).update({'status': status.value});

  Future<void> updateAccountStatus(
    String uid,
    AccountStatus status,
  ) =>
      _users.doc(uid).update({'accountStatus': status.value});

  Future<void> updateCategory(
    String categoryId,
    Map<String, dynamic> data,
  ) =>
      _categories.doc(categoryId).update(data);

  Future<void> deleteCategory(String categoryId) =>
      _categories.doc(categoryId).delete();

  /// Moves every listing in [oldName] to "Uncategorized" (delete guard).
  Future<int> reassignCategoryListings(String oldName) async {
    final snap =
        await _listings.where('category', isEqualTo: oldName).get();
    if (snap.docs.isEmpty) return 0;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'category': 'Uncategorized'});
    }
    await batch.commit();
    return snap.docs.length;
  }

  Future<RatingModel?> getRating(String ratingId) async {
    final snap = await _ratings.doc(ratingId).get();
    final data = snap.data();
    return data == null ? null : RatingModel.fromMap(snap.id, data);
  }

  /// Deletes a review; caller refreshes the rated user's average.
  Future<void> deleteRating(String ratingId) =>
      _ratings.doc(ratingId).delete();
}
