// Admin UI: AdminStats unit tests + the AdminShell rendered at a
// small-phone size with fake data so layout overflows fail the test.
// Firebase-free: services are faked (see AGENTS.md testing rule).

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:swidshop/models/category_model.dart';
import 'package:swidshop/models/payment_model.dart';
import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/models/notification_model.dart';
import 'package:swidshop/models/partner_ad_model.dart';
import 'package:swidshop/models/rating_model.dart';
import 'package:swidshop/models/report_model.dart';
import 'package:swidshop/models/role_request_model.dart';
import 'package:swidshop/models/transaction_model.dart';
import 'package:swidshop/models/user_model.dart';
import 'package:swidshop/providers/admin_provider.dart';
import 'package:swidshop/providers/auth_provider.dart';
import 'package:swidshop/screens/admin/admin_shell.dart';
import 'package:swidshop/services/auth_service.dart';
import 'package:swidshop/services/firestore_service.dart';

class _FakeUser implements User {
  @override
  String get uid => 'admin1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  @override
  Stream<User?> authStateChanges() => Stream.value(_FakeUser());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirestore implements FirestoreService {
  _FakeFirestore({
    required this.users,
    required this.listings,
    required this.txns,
    required this.reports,
    this.payments = const [],
  });

  final List<UserModel> users;
  final List<ListingModel> listings;
  final List<TransactionModel> txns;
  final List<ReportModel> reports;
  final List<PaymentModel> payments;

  @override
  Stream<UserModel?> streamUser(String uid) =>
      Stream.value(users.firstWhere((u) => u.uid == uid));

  @override
  Stream<List<UserModel>> streamAllUsers() => Stream.value(users);

  @override
  Stream<List<ListingModel>> streamAllListings() => Stream.value(listings);

  @override
  Stream<List<TransactionModel>> streamAllTransactions() => Stream.value(txns);

  @override
  Stream<List<ReportModel>> streamAllReports() => Stream.value(reports);

  @override
  Stream<List<PaymentModel>> streamAllPayments() => Stream.value(payments);

  @override
  Stream<List<PartnerAdModel>> streamAllPartnerAds() => Stream.value(const []);

  @override
  Stream<List<RoleRequestModel>> streamAllRoleRequests() => Stream.value([
    RoleRequestModel(
      uid: 'u1',
      currentRole: UserRole.customer,
      requestedRole: UserRole.both,
      reason: 'I also want to buy and bid on items',
      createdAt: DateTime(2026, 10, 4),
    ),
  ]);

  @override
  Stream<List<NotificationModel>> streamNotifications(String uid) =>
      Stream.value(const []);

  @override
  Stream<List<CategoryModel>> streamCategories() => Stream.value(const [
    CategoryModel(categoryId: 'c1', name: 'Vintage Graphic Tees', sortOrder: 0),
    CategoryModel(
      categoryId: 'c2',
      name: 'Outerwear & Jackets with a very long name',
      sortOrder: 1,
    ),
  ]);

  @override
  Future<RatingModel?> getRating(String ratingId) async => RatingModel(
    ratingId: ratingId,
    raterId: 'u2',
    ratedUserId: 'u1',
    transactionId: 't1',
    stars: 1,
    comment: 'Total fake! Do not buy here.',
    createdAt: DateTime(2026, 10, 1),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _user(
  String uid,
  String name,
  UserRole role, {
  AccountStatus status = AccountStatus.active,
  DateTime? createdAt,
  bool trusted = false,
  int deals = 0,
  double rating = 0,
}) => UserModel(
  uid: uid,
  name: name,
  email: '${uid}_with_a_long_address@example.com',
  role: role,
  accountStatus: status,
  createdAt: createdAt,
  trustedBadge: trusted,
  completedTransactions: deals,
  avgRating: rating,
  address: const AddressModel(city: 'Quezon City', province: 'Metro Manila'),
);

TransactionModel _txn(
  String id,
  ListingType type,
  TransactionStatus status,
  DateTime createdAt, {
  double amount = 500,
}) => TransactionModel(
  transactionId: id,
  listingId: 'l_$id',
  buyerId: 'u2',
  sellerId: 'u1',
  type: type,
  status: status,
  amount: amount,
  listingTitle: 'Vintage 1996 Oasis Knebworth Tour Tee long title',
  createdAt: createdAt,
);

void main() {
  group('AdminStats', () {
    final now = DateTime(2026, 10, 15); // Thursday

    test('weeklyDeals buckets by Monday week and skips cancelled', () {
      final weeks = AdminStats.weeklyDeals([
        _txn(
          'a',
          ListingType.buyNow,
          TransactionStatus.completed,
          DateTime(2026, 10, 13),
        ),
        _txn(
          'b',
          ListingType.swap,
          TransactionStatus.pending,
          DateTime(2026, 10, 12),
        ),
        _txn(
          'c',
          ListingType.bid,
          TransactionStatus.cancelled,
          DateTime(2026, 10, 14),
        ),
        _txn(
          'd',
          ListingType.bid,
          TransactionStatus.completed,
          DateTime(2026, 10, 9),
        ),
        _txn(
          'e',
          ListingType.bid,
          TransactionStatus.completed,
          DateTime(2026, 8, 1),
        ),
      ], now: now);
      expect(weeks, hasLength(6));
      expect(weeks.last.week, DateTime(2026, 10, 12));
      expect(weeks.last.buyNow, 1);
      expect(weeks.last.swap, 1);
      expect(weeks.last.bid, 0); // cancelled skipped
      expect(weeks[4].bid, 1);
      expect(weeks.fold<int>(0, (s, w) => s + w.bid), 1); // Aug is out
    });

    test('userGrowth is cumulative per month', () {
      final growth = AdminStats.userGrowth([
        _user('a', 'A', UserRole.customer, createdAt: DateTime(2026, 5, 3)),
        _user('b', 'B', UserRole.both, createdAt: DateTime(2026, 9, 30)),
        _user('c', 'C', UserRole.both, createdAt: DateTime(2026, 10, 1)),
      ], now: now);
      expect(growth.first.month, DateTime(2026, 5));
      expect(growth.first.total, 1);
      expect(growth[4].total, 2); // September
      expect(growth.last.total, 3);
    });

    test('cleanRate ignores open deals and needs a closed one', () {
      expect(AdminStats.cleanRate(const []), isNull);
      expect(
        AdminStats.cleanRate([
          _txn('a', ListingType.buyNow, TransactionStatus.completed, now),
          _txn('b', ListingType.buyNow, TransactionStatus.completed, now),
          _txn('c', ListingType.buyNow, TransactionStatus.completed, now),
          _txn('d', ListingType.buyNow, TransactionStatus.cancelled, now),
          _txn('e', ListingType.buyNow, TransactionStatus.pending, now),
        ]),
        75,
      );
    });

    test('settledVolume counts completed cash deals only', () {
      expect(
        AdminStats.settledVolume([
          _txn(
            'a',
            ListingType.buyNow,
            TransactionStatus.completed,
            now,
            amount: 400,
          ),
          _txn(
            'b',
            ListingType.swap,
            TransactionStatus.completed,
            now,
            amount: 999,
          ),
          _txn(
            'c',
            ListingType.bid,
            TransactionStatus.pending,
            now,
            amount: 999,
          ),
        ]),
        400,
      );
    });

    test('strikes count upheld reports, pending counts open ones', () {
      ReportModel r(String id, ReportStatus s) => ReportModel(
        reportId: id,
        reportedBy: 'x',
        targetType: ReportTargetType.user,
        targetId: 'u1',
        reason: 'r',
        status: s,
      );
      final reports = [
        r('1', ReportStatus.pending),
        r('2', ReportStatus.warned),
        r('3', ReportStatus.dismissed),
        r('4', ReportStatus.suspended),
      ];
      expect(AdminStats.strikesFor(reports, 'u1'), 2);
      expect(AdminStats.pendingFor(reports, 'u1'), 1);
      expect(AdminStats.flaggedIds(reports, ReportTargetType.user), {'u1'});
      expect(AdminStats.flaggedIds(reports, ReportTargetType.listing), isEmpty);
    });

    test('topSellers puts trusted first and skips inactive accounts', () {
      final top = AdminStats.topSellers([
        _user('a', 'A', UserRole.both, deals: 3, rating: 5),
        _user('b', 'B', UserRole.both, deals: 1, rating: 3, trusted: true),
        _user('c', 'C', UserRole.customer, deals: 9, rating: 5),
        _user('d', 'D', UserRole.both, deals: 0),
        _user(
          'e',
          'E',
          UserRole.both,
          deals: 5,
          rating: 5,
          status: AccountStatus.banned,
        ),
      ]);
      expect(top.map((u) => u.uid), ['b', 'a']);
    });

    test('shortCode uses the real id tail', () {
      expect(AdminStats.shortCode('RP', 'abc-xyz9f2a'), '#RP-9F2A');
      expect(AdminStats.shortCode('ID', 'ab'), '#ID-AB');
    });
  });

  testWidgets('Admin shell renders every section on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final users = [
      _user(
        'admin1',
        'Carla Lim',
        UserRole.admin,
        createdAt: now.subtract(const Duration(days: 200)),
      ),
      _user(
        'u1',
        'Mark Santos the Long Named Seller',
        UserRole.both,
        createdAt: now.subtract(const Duration(days: 90)),
        deals: 19,
        rating: 3.2,
        status: AccountStatus.suspended,
      ),
      _user(
        'u2',
        'Tondo Boutique',
        UserRole.both,
        createdAt: now.subtract(const Duration(days: 30)),
        trusted: true,
        deals: 412,
        rating: 4.9,
      ),
      _user(
        'u3',
        'Juan Dela Cruz',
        UserRole.customer,
        createdAt: now.subtract(const Duration(days: 3)),
        status: AccountStatus.banned,
      ),
    ];
    final listings = [
      ListingModel(
        listingId: 'l1',
        sellerId: 'u1',
        title: 'Vintage Nike Windbreaker 90s with an extra long title',
        type: ListingType.buyNow,
        price: 4200,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      ListingModel(
        listingId: 'l2',
        sellerId: 'u2',
        title: '1998 Yohji Yamamoto Knit',
        type: ListingType.swap,
        swapWants: 'Undercover or Issey Miyake pieces',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      ListingModel(
        listingId: 'l3',
        sellerId: 'u2',
        title: 'Oasis Knebworth Tee',
        type: ListingType.bid,
        startingBid: 7400,
        auctionEndAt: now.add(const Duration(hours: 18)),
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      ListingModel(
        listingId: 'l4',
        sellerId: 'u1',
        title: '90s Stussy Big Ol Jeans',
        type: ListingType.buyNow,
        price: 2400,
        status: ListingStatus.expired,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ];
    final txns = [
      _txn(
        't1',
        ListingType.buyNow,
        TransactionStatus.disputed,
        now.subtract(const Duration(days: 1)),
        amount: 6200,
      ),
      _txn(
        't2',
        ListingType.swap,
        TransactionStatus.ongoing,
        now.subtract(const Duration(days: 2)),
      ),
      _txn(
        't3',
        ListingType.bid,
        TransactionStatus.completed,
        now.subtract(const Duration(days: 3)),
        amount: 1450,
      ),
      _txn(
        't4',
        ListingType.buyNow,
        TransactionStatus.cancelled,
        now.subtract(const Duration(days: 4)),
        amount: 2890,
      ),
    ];
    final reports = [
      ReportModel(
        reportId: 'rep1',
        reportedBy: 'u2',
        targetType: ReportTargetType.user,
        targetId: 'u1',
        reason: 'Seller sent misleading wash tag photos for a 90s Stussy tee.',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      ReportModel(
        reportId: 'rep2',
        reportedBy: 'u3',
        targetType: ReportTargetType.listing,
        targetId: 'l1',
        reason: 'Counterfeit',
        createdAt: now.subtract(const Duration(hours: 30)),
      ),
      ReportModel(
        reportId: 'rep3',
        reportedBy: 'u3',
        targetType: ReportTargetType.user,
        targetId: 'u1',
        reason: 'Harassment in chat',
        status: ReportStatus.warned,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      ReportModel(
        reportId: 'rep4',
        reportedBy: 'u1',
        targetType: ReportTargetType.rating,
        targetId: 'rate1',
        reason: 'Slanderous claims without a dispute',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
    ];
    final fs = _FakeFirestore(
      users: users,
      listings: listings,
      txns: txns,
      reports: reports,
      payments: [
        PaymentModel(
          userId: 'u2',
          type: PaymentType.photoPack,
          amount: 99,
          label: 'Photo Pack · 8 photos',
          referenceNo: 'SWD-TEST01',
          createdAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) =>
            AuthProvider(authService: _FakeAuth(), firestoreService: fs),
        child: MaterialApp(home: AdminShell(firestoreService: fs)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Dashboard.
    expect(find.text('Mabuhay, Carla'), findsOneWidget);
    expect(find.text('Deals per Week'), findsOneWidget);
    expect(find.text('Pending Reports'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Top / Trusted Sellers'), 200);
    await tester.pump(const Duration(milliseconds: 400));

    // Navigation is the side bar only (no bottom bar).
    Future<void> tab(String label) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // No bottom navigation bar: its "Admin" tab label is gone.
    expect(find.text('Admin'), findsNothing);

    await tab('Users');
    expect(find.text('Flagged Queue'), findsOneWidget);
    expect(find.textContaining('Suspended'), findsWidgets);

    await tab('Listings');
    expect(find.text('INSPECT'), findsOneWidget);
    expect(find.textContaining('Swap (ISO'), findsOneWidget);

    await tab('Transactions');
    expect(find.text('DISPUTED'), findsOneWidget);
    await tester.drag(find.text('DISPUTED'), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Deal Cancelled'), findsOneWidget);
    expect(find.textContaining('scrow'), findsNothing);

    await tab('Reports');
    expect(find.text('Live Triage Queue'), findsOneWidget);
    expect(find.text('Suspend Account'), findsOneWidget);
    await tester.tap(find.textContaining('Reported Listings'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Remove Listing'), findsOneWidget);

    // Drawer → Ratings & Reviews.
    Future<void> drawer(String label) => tab(label);

    await drawer('Ratings & Reviews');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Review Queue'), findsOneWidget);
    expect(find.text('Remove Review'), findsOneWidget);

    await drawer('Categories');
    expect(find.text('Vintage Graphic Tees'), findsOneWidget);

    // Role Requests: pending request with Approve / Decline.
    await drawer('Role Requests');
    expect(find.text('1 waiting for a decision'), findsOneWidget);
    expect(find.text('Customer + Seller'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pushed admin routes must carry the shell's AdminProvider
    // (regression: "Could not find Provider<AdminProvider>").
    await drawer('Fees');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Recent Payments (1)'), findsOneWidget);
    expect(find.text('Photo Pack · 8 photos'), findsOneWidget);
    expect(find.text('Ref SWD-TEST01'), findsOneWidget);
    expect(find.textContaining('Unpaid ('), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('Unpaid ('))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await drawer('Manage Ads');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('New Ad'), findsOneWidget);
    Navigator.of(tester.element(find.text('New Ad'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // User detail panel from Users.
    await tab('Users');
    await tester.dragUntilVisible(
      find.text('Tondo Boutique'),
      find.text('Flagged Queue'),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tondo Boutique'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('User Detail'), findsOneWidget);
    expect(find.text('Ban Account'), findsOneWidget);
    expect(find.text('Trusted Seller Review'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Transaction History'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Transaction History'), findsOneWidget);
  });
}
