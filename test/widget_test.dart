// SwidShop smoke tests.
//
// These avoid initializing Firebase so they can run as plain unit/widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/core/utils.dart';
import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/models/transaction_model.dart';
import 'package:swidshop/providers/seller_provider.dart';
import 'package:swidshop/models/user_model.dart';
import 'package:swidshop/models/user_private_details_model.dart';
import 'package:swidshop/widgets/auth_widgets.dart';
import 'package:swidshop/widgets/type_badge.dart';

void main() {
  group('Seller Centre', () {
    ListingModel listing(String id, ListingStatus status) =>
        ListingModel(listingId: id, sellerId: 's1', title: id, status: status);
    TransactionModel txn(
      String listingId,
      TransactionStatus status, {
      double amount = 100,
      DateTime? createdAt,
    }) => TransactionModel(
      transactionId: 't_$listingId',
      listingId: listingId,
      buyerId: 'b1',
      sellerId: 's1',
      amount: amount,
      status: status,
      createdAt: createdAt,
    );

    test('tabFor splits sold vs done by transaction status', () {
      final byListing = SellerStats.txnByListing([
        txn('sold1', TransactionStatus.pending),
        txn('done1', TransactionStatus.completed),
      ]);
      expect(
        SellerStats.tabFor(listing('a', ListingStatus.active), byListing),
        MyListingTab.active,
      );
      expect(
        SellerStats.tabFor(listing('sold1', ListingStatus.sold), byListing),
        MyListingTab.sold,
      );
      expect(
        SellerStats.tabFor(listing('done1', ListingStatus.sold), byListing),
        MyListingTab.done,
      );
      expect(
        SellerStats.tabFor(listing('x', ListingStatus.removed), byListing),
        MyListingTab.expired,
      );
    });

    test('salesThisMonth sums this month and skips cancelled', () {
      final now = DateTime(2026, 10, 15);
      final total = SellerStats.salesThisMonth([
        txn(
          'a',
          TransactionStatus.completed,
          amount: 450,
          createdAt: DateTime(2026, 10, 2),
        ),
        txn(
          'b',
          TransactionStatus.pending,
          amount: 300,
          createdAt: DateTime(2026, 10, 14),
        ),
        txn(
          'c',
          TransactionStatus.cancelled,
          amount: 999,
          createdAt: DateTime(2026, 10, 3),
        ),
        txn(
          'd',
          TransactionStatus.completed,
          amount: 800,
          createdAt: DateTime(2026, 9, 30),
        ),
      ], now: now);
      expect(total, 750);
    });

    test('percentChange needs a baseline', () {
      expect(SellerStats.percentChange(1180, 1000), 18);
      expect(SellerStats.percentChange(500, 1000), -50);
      expect(SellerStats.percentChange(500, 0), isNull);
    });

    test('addedWithin counts listings from the last 7 days', () {
      final now = DateTime(2026, 10, 15);
      final ls = [
        listing(
          'a',
          ListingStatus.active,
        ).copyWith(createdAt: DateTime(2026, 10, 14)),
        listing(
          'b',
          ListingStatus.active,
        ).copyWith(createdAt: DateTime(2026, 10, 1)),
      ];
      expect(SellerStats.addedWithin(ls, now: now), 1);
    });

    test('monthlySettled buckets completed deals, oldest first', () {
      final now = DateTime(2026, 10, 15);
      final months = SellerStats.monthlySettled([
        txn(
          'a',
          TransactionStatus.completed,
          amount: 450,
          createdAt: DateTime(2026, 10, 2),
        ),
        txn(
          'b',
          TransactionStatus.completed,
          amount: 200,
          createdAt: DateTime(2026, 8, 9),
        ),
        txn(
          'c',
          TransactionStatus.pending,
          amount: 999,
          createdAt: DateTime(2026, 10, 3),
        ),
      ], now: now);
      expect(months, hasLength(6));
      expect(months.first.month, DateTime(2026, 5));
      expect(months.last.total, 450);
      expect(months[3].total, 200); // August
    });

    test('sellThrough ignores delisted items', () {
      expect(SellerStats.sellThrough(const []), isNull);
      expect(
        SellerStats.sellThrough([
          listing('a', ListingStatus.sold),
          listing('b', ListingStatus.active),
          listing('c', ListingStatus.removed),
        ]),
        0.5,
      );
    });

    test('orderNumber is short and stable', () {
      expect(
        txn(
          'x',
          TransactionStatus.pending,
        ).copyWith(transactionId: 'auction_AbC123xyz').orderNumber,
        'SW-123XYZ',
      );
    });

    test('formatCountdown pads and shows days', () {
      expect(
        AppUtils.formatCountdown(
          const Duration(days: 2, hours: 4, minutes: 5, seconds: 9),
        ),
        '2d 04:05:09',
      );
      expect(AppUtils.formatCountdown(const Duration(seconds: -5)), '00:00:00');
    });

    test('ListingModel keeps swap fields and lock signal', () {
      const swap = ListingModel(
        listingId: 'l1',
        sellerId: 's1',
        title: 'Denim jacket',
        type: ListingType.swap,
        swapWants: 'Cargo pants, size 30',
        swapOnly: false,
        price: 350,
      );
      final restored = ListingModel.fromMap('l1', swap.toMap());
      expect(restored.swapWants, 'Cargo pants, size 30');
      expect(restored.swapOnly, isFalse);
      expect(restored.displayPrice, 350);
      expect(restored.hasBids, isFalse);
      expect(restored.copyWith(currentHighestBid: 400).hasBids, isTrue);
    });
  });

  group('Registration validators', () {
    test('phMobile accepts 10 digits starting with 9', () {
      expect(Validators.phMobile('9171234567'), isNull);
      expect(Validators.phMobile('917 123 4567'), isNull);
      expect(Validators.phMobile('8171234567'), isNotNull);
      expect(Validators.phMobile('917123456'), isNotNull);
      expect(Validators.phMobile('917abc1234567'), isNotNull);
      expect(Validators.phMobile(''), isNotNull);
    });

    test('phPostalCode requires exactly 4 digits', () {
      expect(Validators.phPostalCode('1101'), isNull);
      expect(Validators.phPostalCode('110'), isNotNull);
      expect(Validators.phPostalCode('11a1'), isNotNull);
    });

    test('price range rejects malformed, negative and reversed bounds', () {
      expect(Validators.priceRange('100', '500'), isNull);
      expect(Validators.priceRange('', '500'), isNull);
      expect(Validators.priceRange('one hundred', '500'), isNotNull);
      expect(Validators.priceRange('-1', '500'), isNotNull);
      expect(Validators.priceRange('600', '500'), contains('greater'));
      expect(Validators.priceRange('NaN', ''), isNotNull);
    });

    test('positive numeric fields reject NaN and infinity', () {
      expect(Validators.positiveNumber('10'), isNull);
      expect(Validators.positiveNumber('-1'), isNotNull);
      expect(Validators.positiveNumber('NaN'), isNotNull);
      expect(Validators.positiveNumber('Infinity'), isNotNull);
    });

    test('newPassword needs 8+ chars with a letter and a number', () {
      expect(Validators.newPassword('swidshop1'), isNull);
      expect(Validators.newPassword('short1'), isNotNull);
      expect(Validators.newPassword('lettersonly'), isNotNull);
      expect(Validators.newPassword('12345678'), isNotNull);
    });

    test('isAtLeastAge is inclusive of the 18th birthday', () {
      final now = DateTime(2026, 10, 4);
      expect(
        Validators.isAtLeastAge(DateTime(2008, 10, 4), 18, now: now),
        isTrue,
      );
      expect(
        Validators.isAtLeastAge(DateTime(2008, 10, 5), 18, now: now),
        isFalse,
      );
    });
  });

  test('UserModel treats docs without profileComplete as complete', () {
    final legacy = UserModel.fromMap('u1', {'name': 'Old', 'email': 'o@x.ph'});
    expect(legacy.profileComplete, isTrue);

    const fresh = UserModel(
      uid: 'u2',
      name: 'New',
      email: 'n@x.ph',
      firstName: 'New',
      profileComplete: false,
    );
    final restored = UserModel.fromMap('u2', fresh.toMap());
    expect(restored.profileComplete, isFalse);
    expect(restored.firstName, 'New');
  });

  test('UserPrivateDetails round-trips ID type and phone', () {
    const details = UserPrivateDetails(
      phone: '+639171234567',
      street: '88 Maginhawa St',
      idType: GovIdType.passport,
      idFrontUrl: 'https://res.cloudinary.com/u0sntfxy/image/upload/id.jpg',
    );
    final restored = UserPrivateDetails.fromMap(details.toMap());
    expect(restored.idType, GovIdType.passport);
    expect(restored.idType!.hasBack, isFalse);
    expect(restored.phone, '+639171234567');
    expect(restored.idStatus, 'pending');
  });

  testWidgets('showSuccessPopup shows then closes itself', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold();
          },
        ),
      ),
    );

    var done = false;
    showSuccessPopup(
      ctx,
      title: 'Google account connected',
      message: 'Signed in as juan@example.com.',
      highlight: 'juan@example.com',
    ).then((_) => done = true);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Google account connected'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('Google account connected'), findsNothing);
    expect(done, isTrue);
  });

  testWidgets('StepProgress and GoogleButton render', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StepProgress(step: 2, total: 4, label: 'Role'),
              GoogleButton(),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('TypeBadge shows the correct label for each listing type', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TypeBadge(ListingType.bid))),
    );
    expect(find.text('Bidding'), findsOneWidget);
  });

  test('ListingModel round-trips its core fields through toMap/fromMap', () {
    final model = ListingModel(
      listingId: 'listing_1',
      sellerId: 'seller_1',
      title: 'Vintage Camera',
      description: 'Works great',
      category: 'Electronics',
      type: ListingType.bid,
      startingBid: 500,
      minIncrement: 50,
      images: const ['https://res.cloudinary.com/u0sntfxy/image/upload/a.jpg'],
    );

    final restored = ListingModel.fromMap('listing_1', model.toMap());

    expect(restored.title, 'Vintage Camera');
    expect(restored.type, ListingType.bid);
    expect(restored.startingBid, 500);
    expect(restored.images, hasLength(1));
    expect(restored.status, ListingStatus.active);
  });
}
