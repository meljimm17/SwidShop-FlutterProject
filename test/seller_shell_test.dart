// Renders the Seller Centre at a small-phone size with fake data so layout
// overflows fail the test. Firebase-free: services are faked.

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/models/swap_offer_model.dart';
import 'package:swidshop/models/transaction_model.dart';
import 'package:swidshop/providers/auth_provider.dart';
import 'package:swidshop/providers/seller_provider.dart';
import 'package:swidshop/screens/seller/seller_shell.dart';
import 'package:swidshop/services/auth_service.dart';
import 'package:swidshop/services/firestore_service.dart';

class _FakeFirestore implements FirestoreService {
  _FakeFirestore(this.listings, this.offers, this.txns);

  final List<ListingModel> listings;
  final List<SwapOfferModel> offers;
  final List<TransactionModel> txns;

  @override
  Stream<List<ListingModel>> streamSellerListings(String sellerId) =>
      Stream.value(listings);

  @override
  Stream<List<SwapOfferModel>> streamSellerOffers(String sellerId) =>
      Stream.value(offers);

  @override
  Stream<List<TransactionModel>> streamSellerTransactions(String sellerId) =>
      Stream.value(txns);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Seller Centre tabs render without overflow on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final listings = [
      ListingModel(
        listingId: 'l1',
        sellerId: 's1',
        title: 'Vintage 90s Carhartt J97 Detroit Jacket with a long title',
        category: 'Outerwear & Jackets',
        size: 'L',
        type: ListingType.bid,
        startingBid: 2500,
        minIncrement: 100,
        auctionEndAt: now.add(const Duration(hours: 4)),
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      ListingModel(
        listingId: 'l2',
        sellerId: 's1',
        title: 'Yohji Yamamoto Knit',
        type: ListingType.swap,
        swapWants: 'Undercover / Issey pieces',
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      ListingModel(
        listingId: 'l3',
        sellerId: 's1',
        title: 'Levi’s 501 Big E',
        type: ListingType.buyNow,
        price: 2800,
        status: ListingStatus.expired,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ];

    final seller = SellerProvider(
      firestoreService: _FakeFirestore(listings, const [], const []),
    )..setUser('s1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(
              authService: _FakeAuth(),
              firestoreService: _FakeFirestore(const [], const [], const []),
            ),
          ),
          ChangeNotifierProvider.value(value: seller),
        ],
        child: const MaterialApp(home: SellerShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Seller Dashboard'), findsOneWidget);
    expect(find.text('STORE PULSE'), findsOneWidget);
    expect(find.text('Post New Listing'), findsOneWidget);

    // Bottom nav: Listings tab.
    await tester.tap(find.text('Listings'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Seller Activity Hub'), findsOneWidget);
    expect(find.text('Active Listings'), findsWidgets);

    // Orders and Messages tabs (empty states).
    await tester.tap(find.text('Orders'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No open orders'), findsOneWidget);

    await tester.tap(find.text('Messages'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No conversations yet'), findsOneWidget);

    // Back to Dashboard → Sales History and Analytics.
    await tester.tap(find.text('Dashboard'));
    await tester.pump(const Duration(milliseconds: 400));
    Future<void> center(String text) async {
      await tester.scrollUntilVisible(find.text(text), 150);
      await tester.pump();
      Scrollable.ensureVisible(tester.element(find.text(text)), alignment: 0.5);
      await tester.pump(const Duration(seconds: 2));
    }

    await center('Sales History');
    await tester.tap(find.text('Sales History'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('TOTAL SETTLED'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await center('Analytics');
    await tester.tap(find.text('Analytics'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Sell-through rate'), findsOneWidget);
  });
}
