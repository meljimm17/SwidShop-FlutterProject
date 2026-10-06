import '../core/constants.dart';
import 'report_model.dart';
import 'transaction_model.dart';

/// Trusted Seller eligibility computed from real data. Mirrors
/// `recomputeTrust` in functions/index.js (not deployed yet), which
/// [FirestoreService.recomputeTrust] runs in-app until it is.
///
/// Eligibility is automatic; the badge itself is awarded by an admin.
class TrustReview {
  const TrustReview({
    required this.isSeller,
    required this.avgRating,
    required this.completed,
    required this.completionRate,
    required this.openReports,
  });

  /// Only Customer + Seller accounts can hold the badge.
  final bool isSeller;

  /// Unrounded mean of every rating received (0 without ratings).
  final double avgRating;

  /// Completed deals as the seller.
  final int completed;

  /// completed ÷ (completed + cancelled + disputed), 0–1; 0 when none.
  final double completionRate;

  /// Pending reports against the account, its listings or its ratings.
  final int openReports;

  bool get meetsDeals =>
      completed >= AppConstants.trustedMinCompletedTransactions;
  bool get meetsCompletionRate =>
      completionRate >= AppConstants.trustedMinCompletionRate;
  bool get meetsRating => avgRating >= AppConstants.trustedMinAvgRating;
  bool get meetsReports => openReports == 0;

  bool get eligible =>
      isSeller && meetsDeals && meetsCompletionRate && meetsRating && meetsReports;

  factory TrustReview.evaluate({
    required bool isSeller,
    required Iterable<num> stars,
    required Iterable<TransactionStatus> sellerDeals,
    required int openReports,
  }) {
    final ratings = stars.toList();
    final avg = ratings.isEmpty
        ? 0.0
        : ratings.fold<double>(0, (s, v) => s + v) / ratings.length;
    var completed = 0;
    var resolved = 0;
    for (final s in sellerDeals) {
      switch (s) {
        case TransactionStatus.completed:
          completed++;
          resolved++;
        case TransactionStatus.cancelled:
        case TransactionStatus.disputed:
          resolved++;
        case TransactionStatus.pending:
        case TransactionStatus.ongoing:
          break;
      }
    }
    return TrustReview(
      isSeller: isSeller,
      avgRating: avg,
      completed: completed,
      completionRate: resolved == 0 ? 0 : completed / resolved,
      openReports: openReports,
    );
  }

  /// Pending reports aimed at [uid], one of [listingIds] or [ratingIds].
  static int openReportsFor({
    required String uid,
    required Set<String> listingIds,
    required Set<String> ratingIds,
    required Iterable<ReportModel> reports,
  }) =>
      reports.where((r) {
        if (r.status != ReportStatus.pending) return false;
        return switch (r.targetType) {
          ReportTargetType.user => r.targetId == uid,
          ReportTargetType.listing => listingIds.contains(r.targetId),
          ReportTargetType.rating => ratingIds.contains(r.targetId),
        };
      }).length;
}
