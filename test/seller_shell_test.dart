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
import 'package:swidshop/screens/seller/fee_payments.dart';
import 'package:swidshop/screens/seller/grow_my_shop_screen.dart';
import 'package:swidshop/screens/seller/plans_screen.dart';
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
  Stream<List<TransactionModel>> streamBuyerTransactions(String buyerId) =>
      Stream.value(const []);

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
    // Free plan: analytics is a locked Pro perk (see Plans prompt).
    expect(find.text('Sales Analytics is a Pro perk.'), findsOneWidget);
    expect(find.text('See Plans'), findsOneWidget);
  });

  testWidgets('Monetization screens render without overflow on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final txns = [
      TransactionModel(
        transactionId: 'auction_l1',
        listingId: 'l1',
        buyerId: 'b1',
        sellerId: 's1',
        type: ListingType.bid,
        amount: 2500,
        listingTitle: 'Vintage 90s Carhartt J97 Detroit Jacket',
        status: TransactionStatus.completed,
        createdAt: now.subtract(const Duration(days: 9)),
        feeRate: 0.05,
        feeAmount: 125,
        feeStatus: 'unpaid',
        feeDueAt: now.subtract(const Duration(days: 2)),
      ),
      TransactionModel(
        transactionId: 't2',
        listingId: 'l2',
        buyerId: 'b2',
        sellerId: 's1',
        type: ListingType.buyNow,
        amount: 1000,
        listingTitle: 'Levi’s 501 Big E',
        status: TransactionStatus.completed,
        createdAt: now.subtract(const Duration(days: 1)),
        feeRate: 0.05,
        feeAmount: 50,
        feeStatus: 'paid',
        feeDueAt: now.add(const Duration(days: 6)),
      ),
    ];
    final seller = SellerProvider(
      firestoreService: _FakeFirestore(const [], const [], txns),
    )..setUser('s1');

    Widget host(Widget home) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => AuthProvider(
                authService: _FakeAuth(),
                firestoreService: _FakeFirestore(const [], const [], const []),
              ),
            ),
            ChangeNotifierProvider.value(value: seller),
          ],
          child: MaterialApp(home: home),
        );

    // Seller Centre fee banners (hold + overdue alert with Pay Now).
    final unpaid = unpaidFees(txns);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FeeHoldBanner(onHold: true, manual: false, unpaid: unpaid),
              FeeAlertBanner(unpaid: unpaid),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Your shop is ON HOLD'), findsOneWidget);
    expect(find.text('Overdue platform fees'), findsOneWidget);
    expect(find.text('Pay Now'), findsOneWidget);
    expect(unpaid.length, 1);

    // Grow My Shop hub links every purchase.
    await tester.pumpWidget(host(const GrowMyShopScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in [
      'Plans',
      'Boost My Shop',
      'Photo Pack',
      'Feature a Listing',
      'Platform Fees',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Plans: comparison table + one Subscribe per paid plan.
    await tester.pumpWidget(host(const PlansScreen()));
    await tester.pump();
    expect(find.text('Commission (Bid, Buy Now)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Plans renew manually — nothing is charged automatically.'),
      300,
    );
    await tester.pump();
    expect(find.text('Subscribe', skipOffstage: false), findsNWidgets(2));
  });
}
