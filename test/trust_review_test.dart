import 'package:flutter_test/flutter_test.dart';
import 'package:swidshop/models/report_model.dart';
import 'package:swidshop/models/transaction_model.dart';
import 'package:swidshop/models/trust_review.dart';

List<TransactionStatus> _deals(int completed, {int cancelled = 0}) => [
  for (var i = 0; i < completed; i++) TransactionStatus.completed,
  for (var i = 0; i < cancelled; i++) TransactionStatus.cancelled,
  TransactionStatus.ongoing, // open deals never count either way
];

ReportModel _report(
  ReportTargetType type,
  String target, {
  ReportStatus status = ReportStatus.pending,
}) => ReportModel(
  reportId: 'r-$target',
  reportedBy: 'someone',
  targetType: type,
  targetId: target,
  reason: 'x',
  status: status,
);

void main() {
  group('TrustReview.evaluate', () {
    test('10 deals, 100%, 4.7★, no reports → eligible', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: [5, 5, 5, 5, 4, 5, 5, 4, 5, 4],
        sellerDeals: _deals(10),
        openReports: 0,
      );
      expect(r.completed, 10);
      expect(r.completionRate, 1);
      expect(r.avgRating, closeTo(4.7, 0.001));
      expect(r.eligible, isTrue);
    });

    test('6 deals is not enough (old 5+ rule no longer applies)', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: [5, 5, 5, 5, 5, 5],
        sellerDeals: _deals(6),
        openReports: 0,
      );
      expect(r.meetsDeals, isFalse);
      expect(r.eligible, isFalse);
    });

    test('average below 4.5 fails even with enough deals', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: [4, 4, 5, 4, 5, 4, 4, 5, 4, 4],
        sellerDeals: _deals(10),
        openReports: 0,
      );
      expect(r.avgRating, closeTo(4.3, 0.001));
      expect(r.meetsRating, isFalse);
      expect(r.eligible, isFalse);
    });

    test('completion rate below 90% fails', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: List.filled(10, 5),
        sellerDeals: _deals(10, cancelled: 2), // 10 / 12 = 83%
        openReports: 0,
      );
      expect(r.meetsCompletionRate, isFalse);
      expect(r.eligible, isFalse);
    });

    test('one unresolved report blocks eligibility', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: List.filled(10, 5),
        sellerDeals: _deals(10),
        openReports: 1,
      );
      expect(r.meetsReports, isFalse);
      expect(r.eligible, isFalse);
    });

    test('customer-only accounts are never eligible', () {
      final r = TrustReview.evaluate(
        isSeller: false,
        stars: List.filled(10, 5),
        sellerDeals: _deals(10),
        openReports: 0,
      );
      expect(r.eligible, isFalse);
    });

    test('no ratings → 0 average, not eligible', () {
      final r = TrustReview.evaluate(
        isSeller: true,
        stars: const [],
        sellerDeals: _deals(10),
        openReports: 0,
      );
      expect(r.avgRating, 0);
      expect(r.eligible, isFalse);
    });
  });

  test('openReportsFor counts pending reports on account, listings, ratings', () {
    final reports = [
      _report(ReportTargetType.user, 'seller'),
      _report(ReportTargetType.listing, 'L1'),
      _report(ReportTargetType.rating, 'R1'),
      _report(ReportTargetType.user, 'seller', status: ReportStatus.dismissed),
      _report(ReportTargetType.user, 'someone-else'),
      _report(ReportTargetType.listing, 'not-mine'),
    ];
    expect(
      TrustReview.openReportsFor(
        uid: 'seller',
        listingIds: {'L1', 'L2'},
        ratingIds: {'R1'},
        reports: reports,
      ),
      3,
    );
  });
}
