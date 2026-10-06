// Auction length + live end-time changes (pure logic, Firebase-free).

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:swidshop/core/constants.dart';
import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/providers/auth_provider.dart';
import 'package:swidshop/screens/seller/auction_time_sheet.dart';
import 'package:swidshop/services/auth_service.dart';
import 'package:swidshop/widgets/duration_picker.dart';
import 'package:swidshop/core/utils.dart';
import 'package:swidshop/services/firestore_service.dart';

class _FakeAuth implements AuthService {
  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirestore implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHost(
  WidgetTester tester,
  Widget Function(BuildContext) open,
) async {
  tester.view.physicalSize = const Size(720, 1560);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(
        authService: _FakeAuth(),
        firestoreService: _FakeFirestore(),
      ),
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: open)),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 10, 6, 12);

  testWidgets('Change end time sheet: shorten/extend preview, no overflow', (
    tester,
  ) async {
    final listing = ListingModel(
      listingId: 'l1',
      sellerId: 's1',
      title: 'Vintage jacket',
      type: ListingType.bid,
      startingBid: 100,
      currentHighestBid: 300,
      bidCount: 2,
      auctionEndAt: DateTime.now().add(const Duration(minutes: 30)),
    );
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed: () => showChangeAuctionEndSheet(context, listing),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Change end time'), findsOneWidget);
    expect(
      find.textContaining('everyone who bid will be notified'),
      findsOneWidget,
    );
    // Unchanged: Save disabled.
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save new end time'),
    );
    expect(save().onPressed, isNull);

    await tester.tap(find.text('+ 1 h'));
    await tester.pump();
    expect(find.textContaining(RegExp(r'1 h (29|30) min from now')), findsOneWidget);
    expect(save().onPressed, isNotNull);

    // 30 min auction − 1 h −1 h → in the past: blocked with a reason.
    await tester.tap(find.text('− 1 h'));
    await tester.tap(find.text('− 1 h'));
    await tester.pump();
    expect(find.textContaining('at least 1 min from now'), findsOneWidget);
    expect(save().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Custom length picker: steps and limits', (tester) async {
    Duration? picked;
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed: () async => picked = await showDurationPicker(
          context,
          initial: const Duration(minutes: 30),
          min: AppConstants.minAuctionDuration,
          max: AppConstants.maxAuctionDuration('free'),
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('30 min'), findsOneWidget);
    // 30 → 10 minutes with the minutes "down" arrow (5-minute steps).
    final down = find.byIcon(Icons.keyboard_arrow_down_rounded);
    for (var i = 0; i < 4; i++) {
      await tester.tap(down.at(2));
      await tester.pump();
    }
    expect(find.text('10 min'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, const Duration(minutes: 10));
    expect(tester.takeException(), isNull);
  });

  group('posting lengths', () {
    test('10-minute auctions are a preset and above the minimum', () {
      expect(
        AppConstants.auctionPresets,
        contains(const Duration(minutes: 10)),
      );
      expect(
        const Duration(minutes: 10) >= AppConstants.minAuctionDuration,
        isTrue,
      );
    });

    test('plan maximums: 7 days free/plus, 14 days pro', () {
      expect(AppConstants.maxAuctionDuration('free'), const Duration(days: 7));
      expect(AppConstants.maxAuctionDuration('plus'), const Duration(days: 7));
      expect(AppConstants.maxAuctionDuration('pro'), const Duration(days: 14));
      for (final d in AppConstants.auctionPresets) {
        expect(d <= AppConstants.maxAuctionDuration('free'), isTrue);
      }
    });

    test('durations read naturally', () {
      expect(AppUtils.formatDuration(const Duration(minutes: 10)), '10 min');
      expect(
        AppUtils.formatDuration(const Duration(hours: 1, minutes: 30)),
        '1 h 30 min',
      );
      expect(AppUtils.formatDuration(const Duration(days: 3)), '3 days');
      expect(
        AppUtils.formatDuration(const Duration(days: 1, hours: 6)),
        '1 day 6 h',
      );
    });

    test('countdown text handles the last minute', () {
      final soon = DateTime.now().add(const Duration(seconds: 40));
      expect(AppUtils.timeRemaining(soon), endsWith('s left'));
    });
  });

  group('changing a live auction end time', () {
    String? problem(Duration fromNow, {String plan = 'free'}) =>
        FirestoreService.auctionEndProblem(
          newEnd: now.add(fromNow),
          now: now,
          effectivePlan: plan,
        );

    test('shorten to 10 minutes or extend by a day: allowed', () {
      expect(problem(const Duration(minutes: 10)), isNull);
      expect(problem(const Duration(days: 1)), isNull);
      expect(problem(const Duration(days: 7)), isNull);
    });

    test('must stay at least 1 minute away', () {
      expect(problem(const Duration(seconds: 30)), isNotNull);
      expect(problem(const Duration(minutes: -5)), isNotNull);
      expect(problem(AppConstants.minAuctionTimeLeft), isNull);
    });

    test('cannot exceed the plan maximum from now', () {
      expect(problem(const Duration(days: 8)), contains('Pro'));
      expect(problem(const Duration(days: 13), plan: 'pro'), isNull);
      expect(problem(const Duration(days: 15), plan: 'pro'), isNotNull);
    });
  });
}
