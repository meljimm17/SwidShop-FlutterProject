// Monetization pure-logic tests (no Firebase — see AGENTS.md testing rule).

import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/core/constants.dart';
import 'package:swidshop/models/partner_ad_model.dart';
import 'package:swidshop/models/payment_model.dart';
import 'package:swidshop/models/role_request_model.dart';
import 'package:swidshop/models/swap_offer_model.dart';
import 'package:swidshop/screens/admin/admin_shell.dart';
import 'package:swidshop/screens/auth/role_home.dart';
import 'package:swidshop/screens/customer/home_screen.dart';
import 'package:swidshop/models/user_model.dart';
import 'package:swidshop/providers/admin_provider.dart';
import 'package:swidshop/services/firestore_service.dart';
import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/models/transaction_model.dart';

void main() {
  group('fee constants', () {
    test('plan rates match spec (5/4/3%)', () {
      expect(AppConstants.feeRates['free'], 0.05);
      expect(AppConstants.feeRates['plus'], 0.04);
      expect(AppConstants.feeRates['pro'], 0.03);
    });

    test('due window and reminder days', () {
      expect(AppConstants.feeDueDays, 7);
      expect(AppConstants.feeReminderDays, [1, 3, 6]);
    });

    test('photo limits grow with plan', () {
      expect(AppConstants.photoLimits['free'], 3);
      expect(AppConstants.photoLimits['plus'], 8);
      expect(AppConstants.photoLimits['pro'], 15);
    });

    test('swaps carry no fee by construction (no rate entry)', () {
      expect(AppConstants.feeRates.containsKey('swap'), isFalse);
    });
  });

  group('TransactionModel fee state', () {
    const base = TransactionModel(
      transactionId: 't1',
      listingId: 'l1',
      buyerId: 'b',
      sellerId: 's',
    );

    test('unpaid-but-current is not overdue', () {
      final t = base.copyWith(
        feeStatus: 'unpaid',
        feeAmount: 50,
        feeDueAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(t.feeUnpaid, isTrue);
      expect(t.feeOverdue, isFalse);
    });

    test('unpaid past due is overdue', () {
      final t = base.copyWith(
        feeStatus: 'unpaid',
        feeAmount: 50,
        feeDueAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(t.feeOverdue, isTrue);
    });

    test('paid/void/none are never overdue', () {
      final past = DateTime.now().subtract(const Duration(days: 9));
      for (final s in ['paid', 'void', 'none']) {
        final t = base.copyWith(feeStatus: s, feeDueAt: past);
        expect(t.feeOverdue, isFalse, reason: s);
        expect(t.feeUnpaid, isFalse, reason: s);
      }
    });

    test('fee fields round-trip', () {
      final t = base.copyWith(
        feeRate: 0.05,
        feeAmount: 62.5,
        feeStatus: 'unpaid',
        feeDueAt: DateTime(2026, 10, 12),
      );
      final restored = TransactionModel.fromMap('t1', t.toMap());
      expect(restored.feeRate, 0.05);
      expect(restored.feeAmount, 62.5);
      expect(restored.feeStatus, 'unpaid');
    });
  });

  group('ListingModel perk flags', () {
    test('featured window check', () {
      const l = ListingModel(listingId: 'l', sellerId: 's', title: 'T');
      expect(l.isFeatured, isFalse);
      final on = l.copyWith(
        featuredUntil: DateTime.now().add(const Duration(days: 2)),
      );
      expect(on.isFeatured, isTrue);
      final off = l.copyWith(
        featuredUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(off.isFeatured, isFalse);
    });

    test('hidden defaults to visible on older docs', () {
      const l = ListingModel(listingId: 'l', sellerId: 's', title: 'T');
      final map = l.toMap()..remove('hidden');
      expect(ListingModel.fromMap('l', map).hidden, isFalse);
    });
  });

  group('PaymentModel', () {
    test('reference numbers are SWD-prefixed and unique-ish', () {
      final a = PaymentModel.newReference();
      final b = PaymentModel.newReference();
      expect(a.startsWith('SWD-'), isTrue);
      expect(a, isNot(equals(b)));
    });

    test('round-trips with spec fields', () {
      const p = PaymentModel(
        userId: 'u',
        type: PaymentType.plan,
        amount: 149,
        label: 'Plus plan',
        referenceNo: 'DEMO-ABC123',
        plan: 'plus',
        days: 30,
      );
      final map = p.toMap();
      for (final k in [
        'userId',
        'type',
        'amount',
        'referenceNo',
        'createdAt',
      ]) {
        expect(map.containsKey(k), isTrue, reason: k);
      }
      final restored = PaymentModel.fromMap('p1', map);
      expect(restored.type, 'plan');
      expect(restored.plan, 'plus');
      expect(restored.days, 30);
      expect(restored.amount, 149);
    });

    test('deterministic ids tie payments to what they pay for', () {
      expect(PaymentModel.feeId('t1'), 'fee_t1');
      expect(PaymentModel.photoPackId('l1'), 'photo_pack_l1');
    });

    test('collection is named payments', () {
      expect(AppConstants.paymentsCollection, 'payments');
    });
  });

  group('effective plan', () {
    final now = DateTime(2026, 10, 5, 12);

    test('open window keeps the plan, lapsed window is free', () {
      expect(
        UserModel.effectivePlanOf(
          'pro',
          now.add(const Duration(days: 1)),
          now: now,
        ),
        'pro',
      );
      expect(
        UserModel.effectivePlanOf(
          'pro',
          now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        'free',
      );
    });

    test('no end date (admin-set) stays on; unknown values are free', () {
      expect(UserModel.effectivePlanOf('plus', null, now: now), 'plus');
      expect(UserModel.effectivePlanOf('gold', null, now: now), 'free');
      expect(UserModel.effectivePlanOf('', null, now: now), 'free');
    });

    test('a lapsed Pro seller is charged the free rate', () {
      final u = UserModel(
        uid: 'u',
        name: '',
        email: '',
        plan: 'pro',
        planUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(u.effectivePlan, 'free');
      expect(Fees.rateFor(u.effectivePlan), 0.05);
      expect(u.isVerifiedSeller, isFalse);
    });
  });

  group('Fees', () {
    test('rounded to centavos', () {
      expect(Fees.amountFor(1234, 0.05), 61.7);
      expect(Fees.amountFor(999.99, 0.03), 30.0);
      expect(Fees.amountFor(1000, 0.04), 40);
    });

    test('due 7 days after the deal', () {
      final d = DateTime(2026, 10, 5, 9);
      expect(Fees.dueFrom(d), DateTime(2026, 10, 12, 9));
    });

    test('reminders only on days 1, 3 and 6', () {
      final deal = DateTime(2026, 10, 1, 9);
      final hits = [
        for (var day = 0; day <= 8; day++)
          if (Fees.isReminderDay(deal, deal.add(Duration(days: day, hours: 2))))
            day,
      ];
      expect(hits, [1, 3, 6]);
    });

    test('unknown plan falls back to the free rate', () {
      expect(Fees.rateFor('???'), 0.05);
    });
  });

  group('listing perks', () {
    test('photo cap = max(plan, Photo Pack)', () {
      expect(ListingModel.photoCapOf('free', null), 3);
      expect(ListingModel.photoCapOf('free', 8), 8);
      expect(ListingModel.photoCapOf('plus', null), 8);
      expect(ListingModel.photoCapOf('pro', 8), 15);
    });

    test('perk fields are never written by toMap', () {
      final l = const ListingModel(listingId: 'l', sellerId: 's', title: 'T')
          .copyWith(
            featuredUntil: DateTime(2030),
            highlightUntil: DateTime(2030),
            bumpedAt: DateTime(2026),
            hidden: true,
          );
      final map = l.toMap();
      for (final k in [
        'featuredUntil',
        'highlightUntil',
        'bumpedAt',
        'hidden',
      ]) {
        expect(map.containsKey(k), isFalse, reason: k);
      }
    });

    test('highlight and featured are independent', () {
      final l = const ListingModel(
        listingId: 'l',
        sellerId: 's',
        title: 'T',
      ).copyWith(highlightUntil: DateTime.now().add(const Duration(days: 1)));
      expect(l.isHighlighted, isTrue);
      expect(l.isFeatured, isFalse);
    });

    test('a bump moves an older listing above a newer one', () {
      final old = ListingModel(
        listingId: 'old',
        sellerId: 's',
        title: 'Old',
        createdAt: DateTime(2026, 9, 1),
        bumpedAt: DateTime(2026, 10, 4),
      );
      final fresh = ListingModel(
        listingId: 'new',
        sellerId: 's',
        title: 'New',
        createdAt: DateTime(2026, 10, 3),
      );
      final stale = ListingModel(
        listingId: 'stale',
        sellerId: 's',
        title: 'Stale bump',
        createdAt: DateTime(2026, 8, 1),
        bumpedAt: DateTime(2026, 8, 2),
      );
      final feed = [stale, fresh, old]..sort(FirestoreService.feedOrder);
      expect(feed.map((l) => l.listingId), ['old', 'new', 'stale']);
    });

    test('Buy It Now closes once bids reach it or the auction ends', () {
      final base = ListingModel(
        listingId: 'l',
        sellerId: 's',
        title: 'T',
        type: ListingType.bid,
        buyNowPrice: 500,
        auctionEndAt: DateTime.now().add(const Duration(days: 2)),
      );
      expect(base.buyItNowOpen, isTrue);
      expect(base.copyWith(currentHighestBid: 499).buyItNowOpen, isTrue);
      expect(base.copyWith(currentHighestBid: 500).buyItNowOpen, isFalse);
      expect(
        base
            .copyWith(
              auctionEndAt: DateTime.now().subtract(const Duration(minutes: 1)),
            )
            .buyItNowOpen,
        isFalse,
      );
      expect(base.copyWith(type: ListingType.buyNow).buyItNowOpen, isFalse);
    });

    test('windows extend from the later of now and the current end', () {
      final now = DateTime(2026, 10, 5);
      expect(FirestoreService.extendFrom(null, now), now);
      expect(FirestoreService.extendFrom(DateTime(2026, 10, 1), now), now);
      expect(
        FirestoreService.extendFrom(DateTime(2026, 10, 9), now),
        DateTime(2026, 10, 9),
      );
    });
  });

  group('swap photo offers (no listing needed)', () {
    test('round-trips title + photos and is a photo offer', () {
      const o = SwapOfferModel(
        offerId: 'o1',
        listingId: 'target',
        offeredById: 'u',
        offeredTitle: 'Linen shirt, size M',
        offeredImages: ['https://img/a.jpg', 'https://img/b.jpg'],
        message: 'meet-up only',
      );
      final back = SwapOfferModel.fromMap('o1', o.toMap());
      expect(back.isPhotoOffer, isTrue);
      expect(back.offeredItemId, '');
      expect(back.offeredTitle, 'Linen shirt, size M');
      expect(back.offeredImages, hasLength(2));
    });

    test('older listing offers still parse (no photo fields)', () {
      final old = SwapOfferModel.fromMap('o2', {
        'listingId': 'target',
        'offeredById': 'u',
        'offeredItemId': 'myListing',
        'status': 'pending',
      });
      expect(old.isPhotoOffer, isFalse);
      expect(old.offeredImages, isEmpty);
      expect(old.offeredItemId, 'myListing');
    });

    test('photo offer shows as an item with its photos and title', () {
      const o = SwapOfferModel(
        offerId: 'o1',
        listingId: 'target',
        offeredById: 'u',
        offeredTitle: 'Linen shirt',
        offeredImages: ['a', 'b', 'c'],
      );
      final item = FirestoreService.photoOfferItem(o)!;
      expect(item.title, 'Linen shirt');
      expect(item.images, ['a', 'b', 'c']);
      expect(item.sellerId, 'u');
      const empty = SwapOfferModel(
        offerId: 'x',
        listingId: 't',
        offeredById: 'u',
      );
      expect(FirestoreService.photoOfferItem(empty), isNull);
    });

    test('photo cap and Cloudinary folder stay inside the preset prefix', () {
      expect(AppConstants.maxSwapOfferPhotos, 4);
      expect(AppConstants.swapOfferFolder('abc'), 'listings/swap-abc');
    });
  });

  group('roles: customer + both only, one home, requests', () {
    test('only Customer and Customer + Seller (plus admin) exist', () {
      expect(
        UserRole.values.map((r) => r.value),
        ['customer', 'both', 'admin'],
      );
      expect(UserRole.both.label, 'Customer + Seller');
      expect(UserRole.both.canSell, isTrue);
      expect(UserRole.customer.canSell, isFalse);
    });

    test('a stored legacy seller-only role reads as both', () {
      expect(UserRole.fromValue('seller'), UserRole.both);
      final u = UserModel.fromMap('u', {'name': 'S', 'role': 'seller'});
      expect(u.role, UserRole.both);
      expect(u.legacySellerRole, isTrue);
      expect(u.role.canSell, isTrue);
      final fresh = UserModel.fromMap('v', {'name': 'B', 'role': 'both'});
      expect(fresh.legacySellerRole, isFalse);
      // The flag is never written back.
      expect(u.toMap()['role'], 'both');
    });

    test('every non-admin role lands on the same marketplace Home', () {
      for (final r in [UserRole.customer, UserRole.both]) {
        expect(homeForRole(r), isA<HomeScreen>(), reason: r.value);
      }
      expect(homeForRole(UserRole.admin), isA<AdminShell>());
    });

    test('role request round-trips; only customer/both are requestable', () {
      const r = RoleRequestModel(
        uid: 'u',
        currentRole: UserRole.customer,
        requestedRole: UserRole.both,
        reason: 'want to sell',
      );
      final back = RoleRequestModel.fromMap('u', r.toMap());
      expect(back.isPending, isTrue);
      expect(back.currentRole, UserRole.customer);
      expect(back.requestedRole, UserRole.both);
      expect(back.reason, 'want to sell');
      expect(RoleRequestModel.requestable, [UserRole.customer, UserRole.both]);
      // An old request that asked for 'seller' reads as both.
      final old = RoleRequestModel.fromMap('w', {
        'currentRole': 'customer',
        'requestedRole': 'seller',
      });
      expect(old.requestedRole, UserRole.both);
    });
  });

  group('mergePayments (current + earlier-build records)', () {
    test('a fee saved by the earlier build counts toward revenue', () {
      final legacy = [
        PaymentModel(
          userId: 's',
          type: PaymentType.fee,
          amount: 257.5,
          relatedId: 'auction_x',
          createdAt: DateTime(2026, 10, 5),
        ),
      ];
      final merged = FirestoreService.mergePayments(const [], legacy);
      final by = RevenueStats.byStream(merged, const []);
      expect(by[PaymentType.fee], 257.5);
      expect(RevenueStats.total(by), 257.5);
    });

    test('the same fee in both collections is counted once', () {
      final current = [
        PaymentModel(
          userId: 's',
          type: PaymentType.fee,
          amount: 50,
          relatedId: 't1',
          createdAt: DateTime(2026, 10, 6),
        ),
      ];
      final legacy = [
        PaymentModel(
          userId: 's',
          type: PaymentType.fee,
          amount: 50,
          relatedId: 't1',
          createdAt: DateTime(2026, 10, 5),
        ),
        PaymentModel(
          userId: 's',
          type: PaymentType.boost,
          amount: 99,
          createdAt: DateTime(2026, 10, 4),
        ),
      ];
      final merged = FirestoreService.mergePayments(current, legacy);
      expect(merged.length, 2);
      expect(RevenueStats.total(RevenueStats.byStream(merged, const [])), 149);
      expect(merged.first.createdAt, DateTime(2026, 10, 6)); // newest first
    });
  });

  group('RevenueStats', () {
    final payments = [
      PaymentModel(
        userId: 'a',
        type: PaymentType.fee,
        amount: 50,
        createdAt: DateTime(2026, 10, 5),
      ),
      PaymentModel(
        userId: 'a',
        type: PaymentType.plan,
        amount: 149,
        createdAt: DateTime(2026, 9, 29),
      ),
      PaymentModel(
        userId: 'b',
        type: PaymentType.boost,
        amount: 99,
        createdAt: DateTime(2026, 6, 1),
      ),
    ];
    const ads = [PartnerAdModel(adId: 'ad', pricePaid: 300)];

    test('streams + total include partner ads', () {
      final by = RevenueStats.byStream(payments, ads);
      expect(by[PaymentType.fee], 50);
      expect(by[PaymentType.plan], 149);
      expect(by[PaymentType.boost], 99);
      expect(by[PaymentType.featured], 0);
      expect(by['ad'], 300);
      expect(RevenueStats.total(by), 598);
    });

    test('weekly buckets (Monday start), out-of-range skipped', () {
      final w = RevenueStats.weekly(
        payments,
        weeks: 2,
        now: DateTime(2026, 10, 7),
      );
      expect(w.length, 2);
      expect(w[0].week, DateTime(2026, 9, 28));
      expect(w[0].total, 149);
      expect(w[1].total, 50);
    });

    test('fees: collected, outstanding, overdue; cancelled ignored', () {
      const t = TransactionModel(
        transactionId: 't',
        listingId: 'l',
        buyerId: 'b',
        sellerId: 's',
      );
      final past = DateTime.now().subtract(const Duration(days: 1));
      final f = RevenueStats.fees([
        t.copyWith(feeStatus: 'paid', feeAmount: 10),
        t.copyWith(feeStatus: 'unpaid', feeAmount: 20, feeDueAt: past),
        t.copyWith(
          feeStatus: 'unpaid',
          feeAmount: 5,
          feeDueAt: DateTime.now().add(const Duration(days: 3)),
        ),
        t.copyWith(
          feeStatus: 'unpaid',
          feeAmount: 99,
          status: TransactionStatus.cancelled,
        ),
      ]);
      expect(f.collected, 10);
      expect(f.outstanding, 25);
      expect(f.overdue, 20);
    });

    test('plan + boost counts use live windows only', () {
      final soon = DateTime.now().add(const Duration(days: 3));
      final gone = DateTime.now().subtract(const Duration(days: 3));
      final users = [
        UserModel(
          uid: '1',
          name: '',
          email: '',
          plan: 'plus',
          planUntil: soon,
          boostedUntil: soon,
        ),
        UserModel(uid: '2', name: '', email: '', plan: 'pro', planUntil: soon),
        UserModel(
          uid: '3',
          name: '',
          email: '',
          plan: 'pro',
          planUntil: gone,
          boostedUntil: gone,
        ),
      ];
      final p = RevenueStats.paidPlans(users);
      expect(p.plus, 1);
      expect(p.pro, 1);
      expect(RevenueStats.activeBoosts(users), 1);
    });
  });
}
