import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/bid_model.dart';
import '../models/category_model.dart';
import '../models/chat_message_model.dart';
import '../models/listing_model.dart';
import '../models/notification_model.dart';
import '../models/rating_model.dart';
import '../models/report_model.dart';
import '../models/swap_offer_model.dart';
import '../models/transaction_model.dart';
import '../models/trust_review.dart';
import '../models/user_model.dart';
import '../models/partner_ad_model.dart';
import '../models/role_request_model.dart';
import '../models/payment_model.dart';
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

  /// Rewrites the retired seller-only role to Customer + Seller ('both').
  /// The app already treats 'seller' as both; this just fixes the stored
  /// value. Safe to call repeatedly.
  Future<void> migrateLegacySellerRole(String uid) =>
      _users.doc(uid).update({'role': UserRole.both.value});

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

  /// Device token for fee-reminder pushes (read by the `feeReminders`
  /// function). Private: never on the public user doc.
  Future<void> saveFcmToken(String uid, String token) =>
      _privateDetails(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

  /// Posting is always free, but blocked while the seller is on fee hold
  /// (or suspended/banned).
  Future<String> createListing(ListingModel listing) async {
    final seller = await getUser(listing.sellerId);
    if (seller != null && seller.accountStatus != AccountStatus.active) {
      throw StateError(
        seller.accountStatus == AccountStatus.onHold
            ? 'Your shop is on hold over unpaid fees — pay them to post again.'
            : 'This account cannot post listings.',
      );
    }
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

  /// Newest first by [ListingModel.feedTime] (a Pro Bump moves a listing
  /// back to the top). Hold-hidden items are filtered client-side (missing
  /// `hidden` on older docs means visible).
  static int feedOrder(ListingModel a, ListingModel b) =>
      _newestFirst(a.feedTime, b.feedTime);

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
      final items = snap.docs
          .map((d) => ListingModel.fromMap(d.id, d.data()))
          .where((l) => !l.hidden)
          .toList();
      items.sort(feedOrder);
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
      if (data['status'] != ListingStatus.active.value) {
        throw StateError('This auction has ended.');
      }
      if (data['hidden'] == true) {
        throw StateError('This item is temporarily unavailable.');
      }
      final step = (data['minIncrement'] as num?)?.toDouble() ?? 1;
      final minimum = current + (step <= 0 ? 1 : step);
      if (amount < minimum) {
        throw StateError(
          'Bid must be at least ${minimum.toStringAsFixed(0)}.',
        );
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

  /// Why [newEnd] is not allowed as a LIVE auction's end time, or null.
  /// It must be at least [AppConstants.minAuctionTimeLeft] away and within
  /// the plan's longest auction from now. Pure — unit-tested.
  static String? auctionEndProblem({
    required DateTime newEnd,
    required DateTime now,
    required String effectivePlan,
  }) {
    if (newEnd.isBefore(now.add(AppConstants.minAuctionTimeLeft))) {
      return 'The new end time must be at least '
          '${AppUtils.formatDuration(AppConstants.minAuctionTimeLeft)} from now.';
    }
    final max = AppConstants.maxAuctionDuration(effectivePlan);
    if (newEnd.isAfter(now.add(max))) {
      return 'Auctions can run at most ${AppUtils.formatDuration(max)} from '
          'now${effectivePlan == 'pro' ? '' : ' (Pro: ${AppConstants.maxProAuctionDays} days)'}.';
    }
    return null;
  }

  /// Seller moves a LIVE auction's end time earlier or later (even with
  /// bids). Re-checked inside a transaction: still active, not ended, owned
  /// by [sellerId], new end valid. Every bidder is then notified.
  Future<void> updateAuctionEnd({
    required String listingId,
    required String sellerId,
    required DateTime newEnd,
  }) async {
    final seller = await getUser(sellerId);
    final plan = seller?.effectivePlan ?? 'free';
    final ref = _listings.doc(listingId);
    var title = 'an auction';
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw StateError('Listing not found.');
      final l = ListingModel.fromMap(snap.id, data);
      if (l.sellerId != sellerId) {
        throw StateError('Only the seller can change the end time.');
      }
      if (l.type != ListingType.bid || l.status != ListingStatus.active) {
        throw StateError('This auction is no longer running.');
      }
      final now = DateTime.now();
      final end = l.auctionEndAt;
      if (end == null || !end.isAfter(now)) {
        throw StateError('This auction has already ended.');
      }
      final problem = auctionEndProblem(
        newEnd: newEnd,
        now: now,
        effectivePlan: plan,
      );
      if (problem != null) throw StateError(problem);
      title = l.title;
      tx.update(ref, {'auctionEndAt': Timestamp.fromDate(newEnd)});
    });

    // Tell every bidder (fire-and-forget each: never fails the change).
    try {
      final bids = await _bids.where('listingId', isEqualTo: listingId).get();
      final bidders = {
        for (final d in bids.docs) d.data()['bidderId'] as String? ?? '',
      }..removeWhere((id) => id.isEmpty || id == sellerId);
      for (final uid in bidders) {
        try {
          await addNotification(
            uid,
            NotificationModel(
              type: NotificationType.system,
              message: 'The seller changed the end time of "$title" — it '
                  'now ends ${AppUtils.formatDateTime(newEnd)}.',
              relatedId: 'listing:$listingId',
            ),
          );
        } catch (e) {
          debugPrint('notifyEndChange $uid: $e');
        }
      }
    } catch (e) {
      debugPrint('notifyEndChange: $e');
    }
  }

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

    // Seller plan rate is stamped at deal time (read outside the txn).
    final preListing = await getListing(listingId);
    final feeRate = await _sellerFeeRate(preListing?.sellerId ?? '');

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
        feeRate: feeRate,
        feeAmount: Fees.amountFor(top.amount, feeRate),
        feeStatus: 'unpaid',
        feeDueAt: Fees.dueFrom(DateTime.now()),
      ).toMap();
      txn['createdAt'] = FieldValue.serverTimestamp();
      tx.set(txnRef, txn);
      return txnRef.id;
    }).then((txnId) async {
      // Outside the transaction: tell winner and seller (fire-and-forget
      // each so a notification write can never fail the close itself).
      final winner = top;
      if (txnId == null || winner == null) return txnId;
      final closed = await getListing(listingId);
      final title = closed?.title ?? 'your auction';
      final sellerId = closed?.sellerId ?? '';
      try {
        await addNotification(
          winner.bidderId,
          NotificationModel(
            type: NotificationType.transactionUpdate,
            message: 'You won "$title"! Open the chat to arrange handover.',
            relatedId: 'transaction:$txnId',
          ),
        );
      } catch (e) {
        debugPrint('notifyAuctionWinner: $e');
      }
      try {
        if (sellerId.isNotEmpty) {
          await addNotification(
            sellerId,
            NotificationModel(
              type: NotificationType.transactionUpdate,
              message: '"$title" sold at auction. Open the chat to arrange handover.',
              relatedId: 'transaction:$txnId',
            ),
          );
        }
      } catch (e) {
        debugPrint('notifyAuctionSeller: $e');
      }
      return txnId;
    });
  }

  /// Closes every expired bid listing while the app is open.
  ///
  /// Queries by auction type only, then filters status and end time locally
  /// to avoid needing a composite index.
  Future<void> closeEndedAuctions() async {
    final snap = await _listings
        .where('type', isEqualTo: ListingType.bid.value)
        .get();
    final now = DateTime.now();
    final expired = snap.docs
        .map((doc) => ListingModel.fromMap(doc.id, doc.data()))
        .where(
          (listing) =>
              listing.status == ListingStatus.active &&
              listing.auctionEndAt != null &&
              !listing.auctionEndAt!.isAfter(now),
        )
        .toList();

    for (final listing in expired) {
      try {
        await closeAuctionIfEnded(listing.listingId);
      } catch (e) {
        debugPrint('closeEndedAuction ${listing.listingId}: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // swapOffers
  // ---------------------------------------------------------------------------

  /// Reserves a swap offer id so photo offers can upload to
  /// `listings/swap-{id}` before the document exists.
  String newSwapOfferId() => _swapOffers.doc().id;

  /// Creates a pending offer (uses [SwapOfferModel.offerId] when already
  /// reserved). Fills `sellerId` from the target listing when not provided
  /// (rules require it to match the listing owner). The offered item is a
  /// listing OR a photo offer (title + 1–4 photos).
  Future<String> createSwapOffer(SwapOfferModel offer) async {
    final ref = offer.offerId.isEmpty
        ? _swapOffers.doc()
        : _swapOffers.doc(offer.offerId);
    if (offer.offeredItemId.isEmpty) {
      if (offer.offeredTitle.trim().isEmpty || offer.offeredImages.isEmpty) {
        throw StateError('Add at least one photo and name your item.');
      }
      if (offer.offeredImages.length > AppConstants.maxSwapOfferPhotos) {
        throw StateError(
          'Up to ${AppConstants.maxSwapOfferPhotos} photos per offer.',
        );
      }
    }
    final target = await getListing(offer.listingId);
    if (target == null || target.status != ListingStatus.active) {
      throw StateError('This item is no longer available.');
    }
    if (target.hidden) {
      throw StateError('This item is temporarily unavailable.');
    }
    var sellerId = offer.sellerId;
    if (sellerId.isEmpty) sellerId = target.sellerId;
    if (sellerId.isNotEmpty && sellerId == offer.offeredById) {
      throw StateError('You cannot swap with your own listing.');
    }
    final data =
        offer.copyWith(offerId: ref.id, sellerId: sellerId).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// What the offerer gives: their listing, or — for a photo offer — a
  /// listing-shaped stand-in built from the offer's title and photos.
  /// Never looks up an empty id (Firestore throws on `doc('')`).
  Future<ListingModel?> offeredItemFor(SwapOfferModel offer) async {
    if (offer.offeredItemId.isNotEmpty) {
      return getListing(offer.offeredItemId);
    }
    return photoOfferItem(offer);
  }

  /// Listing-shaped stand-in for a photo offer (null when the offer has
  /// neither photos nor a title). Pure — no Firestore access.
  static ListingModel? photoOfferItem(SwapOfferModel offer) {
    if (offer.offeredImages.isEmpty && offer.offeredTitle.isEmpty) {
      return null;
    }
    return ListingModel(
      listingId: '',
      sellerId: offer.offeredById,
      title: offer.offeredTitle.isEmpty ? 'Offered item' : offer.offeredTitle,
      images: offer.offeredImages,
      type: ListingType.swap,
      createdAt: offer.createdAt,
    );
  }

  // ---------------------------------------------------------------------------
  // role-change requests (roleRequests/{uid}; admin decides)
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _roleRequest(String uid) =>
      _db.collection(AppConstants.roleRequestsCollection).doc(uid);

  /// The user's latest request (null when none).
  Stream<RoleRequestModel?> streamMyRoleRequest(String uid) =>
      _roleRequest(uid).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : RoleRequestModel.fromMap(snap.id, data);
      });

  /// Every request, pending first then newest (admin; client sort).
  Stream<List<RoleRequestModel>> streamAllRoleRequests() => _db
          .collection(AppConstants.roleRequestsCollection)
          .snapshots()
          .map((snap) {
        final items = snap.docs
            .map((d) => RoleRequestModel.fromMap(d.id, d.data()))
            .toList();
        items.sort((a, b) {
          final p = (a.isPending ? 0 : 1) - (b.isPending ? 0 : 1);
          if (p != 0) return p;
          return _compareNullableDates(b.createdAt, a.createdAt);
        });
        return items;
      });

  /// Sends (or replaces) the user's request. Admin role is never
  /// requestable; asking for the current role is rejected.
  Future<void> submitRoleRequest({
    required String uid,
    required UserRole currentRole,
    required UserRole requestedRole,
    String reason = '',
  }) async {
    if (!RoleRequestModel.requestable.contains(requestedRole)) {
      throw StateError('That role cannot be requested.');
    }
    if (requestedRole == currentRole) {
      throw StateError('You already have that role.');
    }
    final data = RoleRequestModel(
      uid: uid,
      currentRole: currentRole,
      requestedRole: requestedRole,
      reason: reason.trim(),
    ).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await _roleRequest(uid).set(data);
  }

  /// Withdraws a pending request.
  Future<void> cancelRoleRequest(String uid) => _roleRequest(uid).delete();

  /// Admin: approve → the user's role changes (their app updates live via
  /// the profile stream) + the request is closed, in one batch; then the
  /// user is notified.
  Future<void> approveRoleRequest(
    RoleRequestModel request, {
    required String adminUid,
  }) async {
    final batch = _db.batch()
      ..update(_users.doc(request.uid), {
        'role': request.requestedRole.value,
      })
      ..update(_roleRequest(request.uid), {
        'status': RoleRequestStatus.approved.value,
        'decidedBy': adminUid,
        'decidedAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
    try {
      await addNotification(
        request.uid,
        NotificationModel(
          type: NotificationType.system,
          message: 'Your role is now ${request.requestedRole.label}. '
              'Your features have been updated.',
          relatedId: 'role:${request.uid}',
        ),
      );
    } catch (e) {
      debugPrint('notifyRoleApproved: $e');
    }
  }

  /// Admin: decline (role unchanged) with an optional note for the user.
  Future<void> rejectRoleRequest(
    RoleRequestModel request, {
    required String adminUid,
    String note = '',
  }) async {
    await _roleRequest(request.uid).update({
      'status': RoleRequestStatus.rejected.value,
      'adminNote': note.trim(),
      'decidedBy': adminUid,
      'decidedAt': FieldValue.serverTimestamp(),
    });
    try {
      await addNotification(
        request.uid,
        NotificationModel(
          type: NotificationType.system,
          message: 'Your request to become ${request.requestedRole.label} '
              'was declined${note.trim().isEmpty ? '.' : ': ${note.trim()}'}',
          relatedId: 'role:${request.uid}',
        ),
      );
    } catch (e) {
      debugPrint('notifyRoleRejected: $e');
    }
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
    // Fee hold blocks swap accepts (enforced here, in the UI and rules).
    final seller = await getUser(offer.sellerId.isNotEmpty
        ? offer.sellerId
        : (await getListing(offer.listingId))?.sellerId ?? '');
    if (seller != null && seller.accountStatus == AccountStatus.onHold) {
      throw StateError(
        'Your shop is on hold over unpaid fees — pay them to accept swaps.',
      );
    }
    final listingRef = _listings.doc(offer.listingId);
    final offerRef = _swapOffers.doc(offer.offerId);
    final txnRef = _transactions.doc('swap_${offer.offerId}');
    final pending = await _swapOffers
        .where('listingId', isEqualTo: offer.listingId)
        .where('status', isEqualTo: SwapOfferStatus.pending.value)
        .get();
    final offeredItem = await offeredItemFor(offer);

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
        swapItemTitle: offeredItem?.title ?? offer.offeredTitle,
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
  ) async {
    await _transactions.doc(transactionId).update({'status': status.value});
    await _refreshTrustForDeal(transactionId);
  }

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

  /// Every deal [uid] is in (buying + selling), newest first. Two equality
  /// queries merged client-side — no composite index needed.
  Stream<List<TransactionModel>> streamTransactionsForUser(String uid) {
    late StreamController<List<TransactionModel>> out;
    var buying = const <TransactionModel>[];
    var selling = const <TransactionModel>[];
    var gotBuying = false;
    var gotSelling = false;
    final subs = <StreamSubscription<List<TransactionModel>>>[];
    void emit() {
      if (!gotBuying || !gotSelling) return;
      final byId = <String, TransactionModel>{
        for (final t in [...buying, ...selling]) t.transactionId: t,
      };
      final all = byId.values.toList()
        ..sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
      out.add(all);
    }

    out = StreamController<List<TransactionModel>>(
      onListen: () {
        subs
          ..add(streamBuyerTransactions(uid).listen((v) {
            buying = v;
            gotBuying = true;
            emit();
          }, onError: out.addError))
          ..add(streamSellerTransactions(uid).listen((v) {
            selling = v;
            gotSelling = true;
            emit();
          }, onError: out.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  /// Latest message in a deal thread (single-field order, no index).
  Stream<ChatMessageModel?> streamLastMessage(String transactionId) =>
      _messages(transactionId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .map((snap) => snap.docs.isEmpty
              ? null
              : ChatMessageModel.fromMap(
                  snap.docs.first.id,
                  snap.docs.first.data(),
                ));

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
      if (message.hasImage) 'imageUrl': message.imageUrl,
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

  /// Reviews about [uid], newest first. Equality filter only + client sort
  /// (where+orderBy needs a composite index, which is not deployed).
  Stream<List<RatingModel>> streamRatingsForUser(String uid) => _ratings
      .where('ratedUserId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final items =
            snap.docs.map((d) => RatingModel.fromMap(d.id, d.data())).toList();
        items.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return items;
      });

  // ---------------------------------------------------------------------------
  // reports
  // ---------------------------------------------------------------------------

  Future<String> createReport(ReportModel report) async {
    final ref = _reports.doc();
    final data = report.copyWith(reportId: ref.id).toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    await _refreshTrustForReport(report.targetType, report.targetId);
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

  /// Admin-only award, guarded by the latest Cloud Function eligibility
  /// result. Badge and seller notification are committed together.
  Future<void> awardTrustedBadge(String uid) async {
    final userRef = _users.doc(uid);
    final notificationRef = _notificationItems(uid).doc();
    await _db.runTransaction((transaction) async {
      final user = await transaction.get(userRef);
      final data = user.data();
      if (data == null) throw StateError('User not found.');
      if (data['trustedBadgeEligible'] != true) {
        throw StateError('This seller is no longer eligible for the badge.');
      }
      if (data['trustedBadge'] == true) return;
      transaction.update(userRef, {'trustedBadge': true});
      transaction.set(notificationRef, {
        'type': NotificationType.system.value,
        'message': 'Congratulations! An admin reviewed your account and '
            'awarded you the Trusted Seller badge.',
        'relatedId': 'trust:$uid',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
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
  /// Refreshes [uid]'s rating average together with the rest of their
  /// Trusted Seller stats (see [recomputeTrust]).
  Future<void> refreshUserRating(String uid) => recomputeTrust(uid);

  /// In-app twin of `recomputeTrust` in functions/index.js, which is NOT
  /// deployed. Recomputes avgRating / completedTransactions /
  /// completionRate / open reports and Trusted Seller eligibility from real
  /// docs. When a seller first becomes eligible every admin gets one
  /// notification (`trust:{uid}` → User Detail); a badge holder who no
  /// longer qualifies loses the badge and is told why. The badge is only
  /// ever granted by an admin ([awardTrustedBadge]). Equality-only queries.
  Future<TrustReview?> recomputeTrust(String uid) async {
    if (uid.isEmpty) return null;
    final ratingsF = _ratings.where('ratedUserId', isEqualTo: uid).get();
    final txnsF = _transactions.where('sellerId', isEqualTo: uid).get();
    final listingsF = _listings.where('sellerId', isEqualTo: uid).get();
    final reportsF = _reports
        .where('status', isEqualTo: ReportStatus.pending.value)
        .get();
    final adminsF =
        _users.where('role', isEqualTo: UserRole.admin.value).get();
    final ratings = await ratingsF;
    final txns = await txnsF;
    final listings = await listingsF;
    final reports = await reportsF;
    final admins = await adminsF;

    final openReports = TrustReview.openReportsFor(
      uid: uid,
      listingIds: {for (final d in listings.docs) d.id},
      ratingIds: {for (final d in ratings.docs) d.id},
      reports: reports.docs.map((d) => ReportModel.fromMap(d.id, d.data())),
    );
    final stars = [
      for (final d in ratings.docs) (d.data()['stars'] as num?) ?? 0,
    ];
    final deals = [
      for (final d in txns.docs)
        TransactionStatus.fromValue(d.data()['status'] as String?),
    ];

    final userRef = _users.doc(uid);
    TrustReview? review;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data();
      if (data == null) return;
      final r = review = TrustReview.evaluate(
        isSeller: UserRole.fromValue(data['role'] as String?) == UserRole.both,
        stars: stars,
        sellerDeals: deals,
        openReports: openReports,
      );
      final hadBadge = data['trustedBadge'] == true;
      final notified = data['trustedEligibilityNotified'] == true;
      final notifyAdmins = r.eligible && !notified && admins.docs.isNotEmpty;
      final removed = hadBadge && !r.eligible;
      tx.update(userRef, {
        'avgRating': (r.avgRating * 10).round() / 10,
        'completedTransactions': r.completed,
        'completionRate': r.completionRate,
        'trustedBadgeEligible': r.eligible,
        'trustedOpenReports': r.openReports,
        'trustedEligibilityNotified': r.eligible && (notified || notifyAdmins),
        'trustedBadge': r.eligible && hadBadge,
      });
      if (notifyAdmins) {
        final rawName = data['name'] as String? ?? '';
        final name = rawName.isNotEmpty
            ? rawName
            : (data['email'] as String? ?? 'A seller');
        for (final a in admins.docs) {
          tx.set(_notificationItems(a.id).doc(), {
            'type': NotificationType.system.value,
            'message': '$name meets the Trusted Seller requirements. Review '
                'their User Details before awarding the badge.',
            'relatedId': 'trust:$uid',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (removed) {
        tx.set(_notificationItems(uid).doc(), {
          'type': NotificationType.system.value,
          'message': 'Your Trusted Seller badge was removed because your '
              'account no longer meets the eligibility requirements.',
          'relatedId': 'trust:$uid',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return review;
  }

  /// Best-effort [recomputeTrust] after a deal / report change; never fails
  /// the action that triggered it.
  Future<void> _refreshTrustQuietly(String uid) async {
    try {
      await recomputeTrust(uid);
    } catch (e) {
      debugPrint('recomputeTrust $uid: $e');
    }
  }

  /// Seller whose Trusted status a report on [type]/[targetId] affects.
  Future<String> _trustOwnerOfReportTarget(
    ReportTargetType type,
    String targetId,
  ) async {
    if (targetId.isEmpty) return '';
    switch (type) {
      case ReportTargetType.user:
        return targetId;
      case ReportTargetType.listing:
        final d = await _listings.doc(targetId).get();
        return d.data()?['sellerId'] as String? ?? '';
      case ReportTargetType.rating:
        final d = await _ratings.doc(targetId).get();
        return d.data()?['ratedUserId'] as String? ?? '';
    }
  }

  Future<void> _refreshTrustForReport(
    ReportTargetType type,
    String targetId,
  ) async {
    try {
      await _refreshTrustQuietly(
        await _trustOwnerOfReportTarget(type, targetId),
      );
    } catch (e) {
      debugPrint('refreshTrustForReport: $e');
    }
  }

  Future<void> _refreshTrustForDeal(String transactionId) async {
    try {
      final d = await _transactions.doc(transactionId).get();
      await _refreshTrustQuietly(d.data()?['sellerId'] as String? ?? '');
    } catch (e) {
      debugPrint('refreshTrustForDeal: $e');
    }
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

    // Seller plan rate is stamped at deal time (read outside the txn).
    final preListing = await getListing(listingId);
    final feeRate = await _sellerFeeRate(preListing?.sellerId ?? '');

    double finalPrice = 0;
    String dealType = ListingType.buyNow.value;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(listingRef);
      final data = snap.data();
      if (data == null) throw StateError('Listing no longer exists.');
      if (data['status'] != ListingStatus.active.value) {
        throw StateError('This item is no longer available.');
      }
      if (data['hidden'] == true) {
        throw StateError('This item is temporarily unavailable.');
      }
      final listingType = data['type'] as String? ?? '';
      final buyNowPrice = (data['buyNowPrice'] as num?)?.toDouble();
      if (listingType == ListingType.buyNow.value) {
        dealType = ListingType.buyNow.value;
        finalPrice = (data['price'] as num?)?.toDouble() ?? 0;
      } else if (listingType == ListingType.bid.value &&
          ListingModel.fromMap(snap.id, data).buyItNowOpen) {
        // Pro add-on: instant-buy price on a running auction whose bids
        // have not reached it yet.
        dealType = ListingType.bid.value;
        finalPrice = buyNowPrice!;
      } else if (listingType == ListingType.bid.value &&
          buyNowPrice != null) {
        throw StateError('Buy It Now is closed for this auction.');
      } else {
        throw StateError('This item is not purchasable right now.');
      }
      if ((data['sellerId'] as String? ?? '') == buyerId) {
        throw StateError('You cannot buy your own listing.');
      }
      final feeAmount = Fees.amountFor(finalPrice, feeRate);
      tx.update(listingRef, {'status': ListingStatus.sold.value});
      tx.set(txnRef, {
        'transactionId': txnRef.id,
        'listingId': listingId,
        'buyerId': buyerId,
        'sellerId': data['sellerId'],
        'type': dealType,
        'amount': finalPrice,
        'listingTitle': data['title'] ?? '',
        'listingImage': (data['images'] as List?)?.firstOrNull ?? '',
        'status': TransactionStatus.pending.value,
        'createdAt': FieldValue.serverTimestamp(),
        'feeRate': feeRate,
        'feeAmount': feeAmount,
        'feeStatus': 'unpaid',
        'feeDueAt': Timestamp.fromDate(Fees.dueFrom(DateTime.now())),
        'paidAt': null,
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
      final fee = Fees.amountFor(finalPrice, feeRate);
      await addNotification(
        listing.sellerId,
        NotificationModel(
          type: NotificationType.transactionUpdate,
          message: 'Your item "${listing.title}" just sold. '
              'Platform fee ${AppUtils.formatCurrency(fee)} due in '
              '${AppConstants.feeDueDays} days.',
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
  ) async {
    await _reports.doc(reportId).update({'status': status.value});
    try {
      final d = await _reports.doc(reportId).get();
      final data = d.data();
      if (data != null) {
        final r = ReportModel.fromMap(d.id, data);
        await _refreshTrustForReport(r.targetType, r.targetId);
      }
    } catch (e) {
      debugPrint('updateReportStatus trust refresh: $e');
    }
  }

  /// Admin moderation. Re-activating also clears any fee hold (manual
  /// flag + hidden listings); the automatic hold re-applies at the next
  /// check if fees are still overdue.
  Future<void> updateAccountStatus(
    String uid,
    AccountStatus status,
  ) async {
    await _users.doc(uid).update({
      'accountStatus': status.value,
      if (status == AccountStatus.active) 'holdManual': false,
    });
    if (status == AccountStatus.active) {
      await setListingsHidden(uid, false);
    }
  }

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

  // ---------------------------------------------------------------------------
  // monetization (demo — simulated GCash, no real money)
  //
  // Every purchase is ONE atomic batch: the `payments` record plus the perk
  // it buys. The perk write carries the payment id (deterministic for fees
  // and photo packs, `lastPaymentId` / `featuredPaymentId` otherwise) so the
  // Firestore rules can check that a matching, brand-new payment exists in
  // the same commit. Nothing is ever half-applied.
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection(AppConstants.paymentsCollection);

  CollectionReference<Map<String, dynamic>> get _partnerAds =>
      _db.collection(AppConstants.partnerAdsCollection);

  /// Seller's commission rate right now (lapsed plans count as free).
  Future<double> _sellerFeeRate(String sellerId) async {
    if (sellerId.isEmpty) return Fees.rateFor('free');
    final seller = await getUser(sellerId);
    return Fees.rateFor(seller?.effectivePlan ?? 'free');
  }

  /// The later of [current] and [now]: windows extend, never shrink.
  static DateTime extendFrom(DateTime? current, DateTime now) =>
      current != null && current.isAfter(now) ? current : now;

  Map<String, dynamic> _paymentData(PaymentModel p, String id) {
    final data = p.toMap();
    data['paymentId'] = id;
    data['createdAt'] = FieldValue.serverTimestamp();
    return data;
  }

  /// Every payment, newest first (admin revenue). Merges the current
  /// `payments` collection with records the earlier build saved in
  /// [AppConstants.legacyPaymentsCollection]; see [mergePayments].
  Stream<List<PaymentModel>> streamAllPayments() {
    late StreamController<List<PaymentModel>> out;
    var current = const <PaymentModel>[];
    var legacy = const <PaymentModel>[];
    var gotCurrent = false;
    var gotLegacy = false;
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    List<PaymentModel> parse(QuerySnapshot<Map<String, dynamic>> snap) => snap
        .docs
        .map((d) => PaymentModel.fromMap(d.id, d.data()))
        .toList();
    void emit() {
      if (gotCurrent && gotLegacy) out.add(mergePayments(current, legacy));
    }

    out = StreamController<List<PaymentModel>>(
      onListen: () {
        subs
          ..add(_payments.snapshots().listen((snap) {
            current = parse(snap);
            gotCurrent = true;
            emit();
          }, onError: out.addError))
          ..add(_db
              .collection(AppConstants.legacyPaymentsCollection)
              .snapshots()
              .listen((snap) {
            legacy = parse(snap);
            gotLegacy = true;
            emit();
          }, onError: (Object e) {
            // Legacy records are optional: never block current revenue.
            debugPrint('legacy payments: $e');
            gotLegacy = true;
            emit();
          }));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  /// Current + legacy payment records, newest first. A fee is counted once
  /// even if both collections hold a record for the same deal.
  static List<PaymentModel> mergePayments(
    List<PaymentModel> current,
    List<PaymentModel> legacy,
  ) {
    final paidFees = {
      for (final p in current)
        if (p.type == PaymentType.fee && p.relatedId.isNotEmpty) p.relatedId,
    };
    final all = [
      ...current,
      for (final p in legacy)
        if (!(p.type == PaymentType.fee && paidFees.contains(p.relatedId))) p,
    ]..sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
    return all;
  }

  /// Plus / Pro for [AppConstants.planDays]. Renewing the active plan
  /// extends it; switching plans starts the new one today.
  Future<DateTime> purchasePlan({
    required String uid,
    required String plan,
    required String referenceNo,
  }) async {
    final price = AppConstants.planPrices[plan];
    if (price == null) throw StateError('Unknown plan.');
    final user = await getUser(uid);
    if (user == null) throw StateError('Profile not found.');
    final now = DateTime.now();
    final base =
        user.effectivePlan == plan ? extendFrom(user.planUntil, now) : now;
    final until = base.add(const Duration(days: AppConstants.planDays));
    final payRef = _payments.doc();
    final batch = _db.batch()
      ..set(
        payRef,
        _paymentData(
          PaymentModel(
            userId: uid,
            type: PaymentType.plan,
            amount: price,
            label: '${_cap(plan)} plan · ${AppConstants.planDays} days',
            referenceNo: referenceNo,
            plan: plan,
            days: AppConstants.planDays,
          ),
          payRef.id,
        ),
      )
      ..update(_users.doc(uid), {
        'plan': plan,
        'planUntil': Timestamp.fromDate(until),
        'lastPaymentId': payRef.id,
      });
    await batch.commit();
    return until;
  }

  /// Shop boost of [days] (3/7/14), stacking onto an active boost.
  Future<DateTime> purchaseBoost({
    required String uid,
    required int days,
    required String referenceNo,
  }) async {
    final price = AppConstants.boostPrices[days];
    if (price == null) throw StateError('Unknown boost length.');
    final user = await getUser(uid);
    if (user == null) throw StateError('Profile not found.');
    final until =
        extendFrom(user.boostedUntil, DateTime.now()).add(Duration(days: days));
    final payRef = _payments.doc();
    final batch = _db.batch()
      ..set(
        payRef,
        _paymentData(
          PaymentModel(
            userId: uid,
            type: PaymentType.boost,
            amount: price,
            label: 'Shop boost · $days days',
            referenceNo: referenceNo,
            days: days,
          ),
          payRef.id,
        ),
      )
      ..update(_users.doc(uid), {
        'boostedUntil': Timestamp.fromDate(until),
        'lastPaymentId': payRef.id,
      });
    await batch.commit();
    return until;
  }

  /// Featured slot on one of [uid]'s active listings, stacking onto an
  /// active one.
  Future<DateTime> purchaseFeatured({
    required String uid,
    required String listingId,
    required String referenceNo,
  }) async {
    final listing = await getListing(listingId);
    if (listing == null || listing.sellerId != uid) {
      throw StateError('Listing not found.');
    }
    if (listing.status != ListingStatus.active) {
      throw StateError('Only active listings can be featured.');
    }
    const days = AppConstants.featuredDays;
    final until = extendFrom(listing.featuredUntil, DateTime.now())
        .add(const Duration(days: days));
    final payRef = _payments.doc();
    final batch = _db.batch()
      ..set(
        payRef,
        _paymentData(
          PaymentModel(
            userId: uid,
            type: PaymentType.featured,
            amount: AppConstants.featuredPrice,
            label: 'Featured · ${listing.title}',
            referenceNo: referenceNo,
            relatedId: listingId,
            days: days,
          ),
          payRef.id,
        ),
      )
      ..update(_listings.doc(listingId), {
        'featuredUntil': Timestamp.fromDate(until),
        'featuredPaymentId': payRef.id,
      });
    await batch.commit();
    return until;
  }

  /// True when [uid] already bought the Photo Pack for [listingId].
  Future<bool> hasPhotoPack(String uid, String listingId) async {
    final snap = await _payments.doc(PaymentModel.photoPackId(listingId)).get();
    return snap.exists && snap.data()?['userId'] == uid;
  }

  /// One-time Photo Pack (8 photos) for [listingId]. The listing may not
  /// exist yet (pack bought while composing): the payment is recorded and
  /// `createListing` stamps the limit. Re-buying is never charged twice.
  Future<void> purchasePhotoPack({
    required String uid,
    required String listingId,
    required String title,
    required String referenceNo,
  }) async {
    final payRef = _payments.doc(PaymentModel.photoPackId(listingId));
    final listingSnap = await _listings.doc(listingId).get();
    final exists = listingSnap.exists;
    if (exists && listingSnap.data()?['sellerId'] != uid) {
      throw StateError('Listing not found.');
    }
    final batch = _db.batch();
    if (!await hasPhotoPack(uid, listingId)) {
      batch.set(
        payRef,
        _paymentData(
          PaymentModel(
            userId: uid,
            type: PaymentType.photoPack,
            amount: AppConstants.photoPackPrice,
            label: 'Photo Pack · $title',
            referenceNo: referenceNo,
            relatedId: listingId,
          ),
          payRef.id,
        ),
      );
    }
    if (exists) {
      batch.update(_listings.doc(listingId), {
        'photoLimit': AppConstants.photoLimits['pack'],
      });
    }
    await batch.commit();
  }

  /// Pro perk: back to the top of the feed, once per
  /// [AppConstants.bumpCooldown] per listing.
  Future<void> bumpListing(ListingModel listing) async {
    final last = listing.bumpedAt;
    if (last != null &&
        DateTime.now().difference(last) < AppConstants.bumpCooldown) {
      throw StateError('Already bumped — try again tomorrow.');
    }
    await _listings
        .doc(listing.listingId)
        .update({'bumpedAt': FieldValue.serverTimestamp()});
  }

  /// Pro perk: coral border + Hot tag for [AppConstants.highlightDays].
  Future<DateTime> highlightListing(String listingId) async {
    final until = DateTime.now()
        .add(const Duration(days: AppConstants.highlightDays));
    await _listings
        .doc(listingId)
        .update({'highlightUntil': Timestamp.fromDate(until)});
    return until;
  }

  /// Cancels a deal AND voids its platform fee (swaps stay 'none').
  Future<void> cancelTransaction(String transactionId) async {
    final snap = await _transactions.doc(transactionId).get();
    final data = snap.data();
    if (data == null) return;
    final update = <String, dynamic>{
      'status': TransactionStatus.cancelled.value,
    };
    final wasUnpaid = (data['feeStatus'] as String? ?? 'none') == 'unpaid';
    if (wasUnpaid) update['feeStatus'] = 'void';
    await _transactions.doc(transactionId).update(update);
    await _refreshTrustQuietly(data['sellerId'] as String? ?? '');
    // A voided overdue fee may be what held the seller.
    if (wasUnpaid) {
      try {
        await recomputeFeeHold(data['sellerId'] as String? ?? '');
      } catch (e) {
        debugPrint('cancelTransaction hold refresh: $e');
      }
    }
  }

  /// Pays ONE fee (see [payFees]).
  Future<int> payFee({
    required String transactionId,
    required String sellerId,
    required String referenceNo,
  }) =>
      payFees(
        sellerId: sellerId,
        transactionIds: [transactionId],
        referenceNo: referenceNo,
      );

  /// Pays the given unpaid fees under one reference: per fee, a `payments`
  /// record `fee_{transactionId}` + feeStatus 'paid' in one batch. When no
  /// overdue fee is left, the same batch lifts an automatic fee hold (an
  /// admin's manual hold stays). Returns how many fees were paid; fees that
  /// are already paid/void are skipped, never charged twice.
  Future<int> payFees({
    required String sellerId,
    required List<String> transactionIds,
    required String referenceNo,
  }) async {
    if (sellerId.isEmpty || transactionIds.isEmpty) return 0;
    final wanted = transactionIds.toSet();
    final all =
        await _transactions.where('sellerId', isEqualTo: sellerId).get();
    final now = DateTime.now();
    final toPay = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var overdueLeft = false;
    for (final d in all.docs) {
      final data = d.data();
      if ((data['feeStatus'] as String? ?? 'none') != 'unpaid') continue;
      if (wanted.contains(d.id)) {
        toPay.add(d);
        continue;
      }
      final due = (data['feeDueAt'] as Timestamp?)?.toDate();
      if (due != null && !due.isAfter(now)) overdueLeft = true;
    }
    if (toPay.isEmpty) {
      throw StateError('These fees are already settled.');
    }

    final user = await getUser(sellerId);
    final lift = user != null &&
        user.accountStatus == AccountStatus.onHold &&
        !user.holdManual &&
        !overdueLeft;

    // 2 writes per fee; stay well under the 500-write batch cap.
    const perBatch = 200;
    for (var i = 0; i < toPay.length; i += perBatch) {
      final chunk = toPay.skip(i).take(perBatch).toList();
      final last = i + perBatch >= toPay.length;
      final batch = _db.batch();
      for (final d in chunk) {
        final data = d.data();
        final payRef = _payments.doc(PaymentModel.feeId(d.id));
        batch
          ..set(
            payRef,
            _paymentData(
              PaymentModel(
                userId: sellerId,
                type: PaymentType.fee,
                amount: (data['feeAmount'] as num?)?.toDouble() ?? 0,
                label: 'Platform fee · ${data['listingTitle'] ?? 'deal'}',
                referenceNo: referenceNo,
                relatedId: d.id,
              ),
              payRef.id,
            ),
          )
          ..update(d.reference, {
            'feeStatus': 'paid',
            'paidAt': FieldValue.serverTimestamp(),
          });
      }
      if (last && lift) {
        batch.update(_users.doc(sellerId), {
          'accountStatus': AccountStatus.active.value,
          'lastPaymentId': PaymentModel.feeId(chunk.first.id),
        });
      }
      await batch.commit();
    }
    if (lift) await setListingsHidden(sellerId, false);
    return toPay.length;
  }

  /// Automatic fee hold from the ledger: any overdue unpaid fee → on_hold +
  /// hide active listings. Lifting without a payment (e.g. the overdue deal
  /// was cancelled) is attempted here and also done daily by the
  /// `feeReminders` function. Never touches suspended/banned accounts or an
  /// admin's manual hold, never touches Auth.
  Future<void> recomputeFeeHold(String sellerId) async {
    if (sellerId.isEmpty) return;
    final user = await getUser(sellerId);
    if (user == null) return;
    if (user.accountStatus == AccountStatus.suspended ||
        user.accountStatus == AccountStatus.banned) {
      return;
    }
    final snap =
        await _transactions.where('sellerId', isEqualTo: sellerId).get();
    final now = DateTime.now();
    final overdue = snap.docs.any((d) {
      final data = d.data();
      if ((data['feeStatus'] as String? ?? 'none') != 'unpaid') return false;
      final due = (data['feeDueAt'] as Timestamp?)?.toDate();
      return due != null && !due.isAfter(now);
    });
    if (overdue && user.accountStatus == AccountStatus.active) {
      await _users
          .doc(sellerId)
          .update({'accountStatus': AccountStatus.onHold.value});
      await setListingsHidden(sellerId, true);
    } else if (!overdue &&
        user.accountStatus == AccountStatus.onHold &&
        !user.holdManual) {
      await _users
          .doc(sellerId)
          .update({'accountStatus': AccountStatus.active.value});
      await setListingsHidden(sellerId, false);
    }
  }

  /// Admin: manual hold (sticks until an admin lifts it) or lift. Refuses
  /// suspended/banned accounts — a hold must never replace a ban.
  Future<void> adminSetFeeHold(String sellerId, {required bool hold}) async {
    final user = await getUser(sellerId);
    if (user == null) throw StateError('User not found.');
    if (user.accountStatus == AccountStatus.suspended ||
        user.accountStatus == AccountStatus.banned) {
      throw StateError(
        'This account is ${user.accountStatus.value} — re-activate it from '
        'Users first.',
      );
    }
    await _users.doc(sellerId).update({
      'accountStatus':
          hold ? AccountStatus.onHold.value : AccountStatus.active.value,
      'holdManual': hold,
    });
    await setListingsHidden(sellerId, hold);
  }

  /// Flips the customer-visibility flag on a seller's ACTIVE listings.
  Future<void> setListingsHidden(String sellerId, bool hidden) async {
    final snap =
        await _listings.where('sellerId', isEqualTo: sellerId).get();
    final docs = snap.docs
        .where((d) =>
            d.data()['status'] == ListingStatus.active.value &&
            (d.data()['hidden'] == true) != hidden)
        .toList();
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      for (final d in docs.skip(i).take(400)) {
        batch.update(d.reference, {'hidden': hidden});
      }
      await batch.commit();
    }
  }

  /// True when [uid] got a fee reminder for [transactionId] in the last
  /// [hours] (equality query only — no index needed).
  Future<bool> _recentFeeReminder(
    String uid,
    String transactionId, {
    int hours = 20,
  }) async {
    final snap = await _notificationItems(uid)
        .where('relatedId', isEqualTo: 'transaction:$transactionId')
        .get();
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return snap.docs.any((d) {
      final data = d.data();
      if (data['type'] != NotificationType.transactionUpdate.value) {
        return false;
      }
      final msg = (data['message'] as String? ?? '').toLowerCase();
      if (!msg.contains('platform fee')) return false;
      final at = (data['createdAt'] as Timestamp?)?.toDate();
      return at != null && at.isAfter(cutoff);
    });
  }

  /// Client-side stand-in for the undeployed schedulers (runs when the
  /// Seller Centre opens): expires the seller's boost/plan/feature/
  /// highlight windows, sends fee reminders (REMINDER_DAYS + overdue,
  /// deduped) and applies/lifts the automatic fee hold. Each step is
  /// best-effort so one failure never blocks the rest.
  Future<void> runSellerMaintenance(String uid) async {
    if (uid.isEmpty) return;
    final now = DateTime.now();
    final user = await getUser(uid);
    if (user == null) return;

    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e) {
        debugPrint('sellerMaintenance.$name: $e');
      }
    }

    await step('expireUser', () async {
      final update = <String, dynamic>{};
      if (user.boostedUntil != null && !user.boostedUntil!.isAfter(now)) {
        update['boostedUntil'] = null;
      }
      if (user.plan != 'free' &&
          user.planUntil != null &&
          !user.planUntil!.isAfter(now)) {
        update['plan'] = 'free';
        update['planUntil'] = null;
      }
      if (update.isNotEmpty) await _users.doc(uid).update(update);
    });

    await step('expireListings', () async {
      final mine = await _listings.where('sellerId', isEqualTo: uid).get();
      final batch = _db.batch();
      var n = 0;
      for (final d in mine.docs) {
        final update = <String, dynamic>{};
        for (final field in const ['featuredUntil', 'highlightUntil']) {
          final end = (d.data()[field] as Timestamp?)?.toDate();
          if (end != null && !end.isAfter(now)) update[field] = null;
        }
        if (update.isNotEmpty) {
          batch.update(d.reference, update);
          n++;
        }
      }
      if (n > 0) await batch.commit();
    });

    await step('feeReminders', () async {
      final txns = await _transactions.where('sellerId', isEqualTo: uid).get();
      for (final d in txns.docs) {
        final data = d.data();
        if ((data['feeStatus'] as String? ?? 'none') != 'unpaid') continue;
        final created = (data['createdAt'] as Timestamp?)?.toDate();
        final due = (data['feeDueAt'] as Timestamp?)?.toDate();
        if (created == null) continue;
        final overdue = due != null && !due.isAfter(now);
        final title = (data['listingTitle'] as String? ?? '').isEmpty
            ? 'a deal'
            : '"${data['listingTitle']}"';
        final amount =
            AppUtils.formatCurrency((data['feeAmount'] as num?)?.toDouble());
        String? message;
        if (overdue) {
          message = 'Platform fee $amount for $title is OVERDUE — pay now '
              'to lift the hold on your shop.';
        } else if (Fees.isReminderDay(created, now)) {
          message = 'Reminder: platform fee $amount for $title is due '
              '${due == null ? 'soon' : AppUtils.formatDate(due)}.';
        }
        if (message == null || await _recentFeeReminder(uid, d.id)) continue;
        await addNotification(
          uid,
          NotificationModel(
            type: NotificationType.transactionUpdate,
            message: message,
            relatedId: 'transaction:${d.id}',
          ),
        );
      }
    });

    await step('feeHold', () => recomputeFeeHold(uid));
  }

  /// Users with a live shop boost (client-side date check, no ranges).
  Stream<List<UserModel>> streamBoostedSellers() =>
      _users.snapshots().map((snap) {
        return snap.docs
            .map((d) => UserModel.fromMap(d.id, d.data()))
            .where((u) => u.isBoosted)
            .toList();
      });

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // -- partner ads ---------------------------------------------------------

  Stream<List<PartnerAdModel>> streamAllPartnerAds() =>
      _partnerAds.snapshots().map((snap) {
        final ads = snap.docs
            .map((d) => PartnerAdModel.fromMap(d.id, d.data()))
            .toList();
        ads.sort((a, b) => _compareNullableDates(b.createdAt, a.createdAt));
        return ads;
      });

  Future<String> createPartnerAd(PartnerAdModel ad) async {
    final ref = _partnerAds.doc();
    final data = ad.toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set({...data, 'adId': ref.id});
    return ref.id;
  }

  Future<void> updatePartnerAd(String adId, Map<String, dynamic> data) =>
      _partnerAds.doc(adId).update(data);

  Future<void> deletePartnerAd(String adId) =>
      _partnerAds.doc(adId).delete();
}
