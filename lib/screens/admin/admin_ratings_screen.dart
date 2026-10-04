import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/rating_model.dart';
import '../../models/report_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/admin_provider.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

enum _StarFilter { all, one, two, threePlus }

/// Ratings & Reviews: flagged-review queue (Phase 4.7).
///
/// Source: `reports` with targetType=='rating' (targetId = ratingId).
/// Removing deletes the review and refreshes the rated user's average;
/// Keep & Dismiss only closes the flag.
class AdminRatingsScreen extends StatefulWidget {
  const AdminRatingsScreen({super.key});

  @override
  State<AdminRatingsScreen> createState() => _AdminRatingsScreenState();
}

class _AdminRatingsScreenState extends State<AdminRatingsScreen> {
  /// ratingId → review (null = deleted). Fetched once per id.
  final Map<String, RatingModel?> _ratings = {};
  final Set<String> _loading = {};
  _StarFilter _filter = _StarFilter.all;

  void _ensureLoaded(AdminProvider a, Iterable<String> ids) {
    for (final id in ids) {
      if (_ratings.containsKey(id) || _loading.contains(id)) continue;
      _loading.add(id);
      a.firestore
          .getRating(id)
          .then((r) {
            if (!mounted) return;
            setState(() {
              _ratings[id] = r;
              _loading.remove(id);
            });
          })
          .catchError((Object e) {
            debugPrint('getRating: $e');
            if (mounted) setState(() => _loading.remove(id));
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final all = a.reports
        .where((r) => r.targetType == ReportTargetType.rating)
        .toList();
    final queue = all.where((r) => r.status == ReportStatus.pending).toList()
      ..sort(
        (x, y) => (x.createdAt ?? DateTime.now()).compareTo(
          y.createdAt ?? DateTime.now(),
        ),
      );
    _ensureLoaded(a, queue.map((r) => r.targetId));

    int stars(ReportModel r) => _ratings[r.targetId]?.stars ?? 0;
    bool matches(ReportModel r, _StarFilter f) => switch (f) {
      _StarFilter.all => true,
      _StarFilter.one => stars(r) == 1,
      _StarFilter.two => stars(r) == 2,
      _StarFilter.threePlus => stars(r) >= 3,
    };
    final shown = queue.where((r) => matches(r, _filter)).toList();
    final resolved = all.length - queue.length;
    final progress = all.isEmpty ? 1.0 : resolved / all.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        AdminCard(
          color: AppColors.mist,
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.coralDeep),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Review Queue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (queue.isNotEmpty)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${queue.length}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.coralDeep,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Flagged Pending',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.coralDeep,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  color: AppColors.coralDeep,
                  backgroundColor: AppColors.line,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$resolved of ${all.length} flags resolved',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}% done',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.coralDeep,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PillRow<_StarFilter>(
          padding: EdgeInsets.zero,
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          options: [
            PillOption(_StarFilter.all, 'All Flagged ${queue.length}'),
            PillOption(
              _StarFilter.one,
              '1-Star ${queue.where((r) => matches(r, _StarFilter.one)).length}',
            ),
            PillOption(
              _StarFilter.two,
              '2-Star ${queue.where((r) => matches(r, _StarFilter.two)).length}',
            ),
            PillOption(
              _StarFilter.threePlus,
              '3-Star+ ${queue.where((r) => matches(r, _StarFilter.threePlus)).length}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No flagged reviews.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _FlaggedReview(
              key: ValueKey(r.reportId),
              report: r,
              rating: _ratings[r.targetId],
              loading: !_ratings.containsKey(r.targetId),
              onRemoved: () => setState(() => _ratings[r.targetId] = null),
            ),
          ),
      ],
    );
  }
}

class _FlaggedReview extends StatefulWidget {
  const _FlaggedReview({
    super.key,
    required this.report,
    required this.rating,
    required this.loading,
    required this.onRemoved,
  });

  final ReportModel report;
  final RatingModel? rating;
  final bool loading;
  final VoidCallback onRemoved;

  @override
  State<_FlaggedReview> createState() => _FlaggedReviewState();
}

class _FlaggedReviewState extends State<_FlaggedReview> {
  bool _busy = false;

  Future<void> _remove(RatingModel rating) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Remove this review?',
      message:
          "The review is deleted and the rated user's average is recalculated.",
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final fs = context.read<AdminProvider>().firestore;
    try {
      await fs.deleteRating(rating.ratingId);
      await fs.refreshUserRating(rating.ratedUserId);
      await fs.updateReportStatus(widget.report.reportId, ReportStatus.removed);
      widget.onRemoved();
    } catch (e) {
      debugPrint('removeReview: $e');
      if (mounted) {
        setState(() => _busy = false);
        showAdminError(context, 'Could not remove. Try again.');
      }
    }
  }

  Future<void> _dismiss() async {
    setState(() => _busy = true);
    try {
      await context.read<AdminProvider>().firestore.updateReportStatus(
        widget.report.reportId,
        ReportStatus.dismissed,
      );
    } catch (e) {
      debugPrint('dismissFlag: $e');
      if (mounted) {
        setState(() => _busy = false);
        showAdminError(context, 'Could not dismiss. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const AdminCard(
        child: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final rating = widget.rating;
    if (rating == null) {
      return AdminCard(
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Review already deleted.',
                style: TextStyle(color: AppColors.gray),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _dismiss,
              child: const Text('Clear from queue'),
            ),
          ],
        ),
      );
    }

    final a = context.watch<AdminProvider>();
    final rated = a.user(rating.ratedUserId);
    TransactionModel? txn;
    for (final t in a.transactions) {
      if (t.transactionId == rating.transactionId) {
        txn = t;
        break;
      }
    }
    final reason = widget.report.reason;

    return AdminCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  a.nameOf(rating.raterId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward,
                  size: 15,
                  color: AppColors.coralDeep,
                ),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () => openAdminUserDetail(context, rating.ratedUserId),
                  child: Text(
                    a.nameOf(rating.ratedUserId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.coralDeep,
                    ),
                  ),
                ),
              ),
              if (rated != null) ...[
                const SizedBox(width: 6),
                SoftPill(
                  '★ ${rated.avgRating.toStringAsFixed(1)} avg',
                  color: AppColors.gray,
                  fontSize: 10.5,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rating.createdAt == null
                ? ''
                : DateFormat('MMM d • h:mm a').format(rating.createdAt!),
            style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SoftPill(
                '${rating.stars}.0',
                color: const Color(0xFF9A6200),
                icon: Icons.star_outline_rounded,
              ),
              if (txn != null)
                SoftPill(
                  '${typeLabel(txn.type)} ${txn.orderNumber}',
                  color: typeColor(txn.type),
                  icon: typeIcon(txn.type),
                ),
            ],
          ),
          if (txn != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  TaggedThumb(
                    url: txn.listingImage,
                    width: 52,
                    height: 52,
                    radius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CapsLabel(switch (txn.type) {
                          ListingType.buyNow => 'Purchased item',
                          ListingType.bid => 'Won item',
                          ListingType.swap => 'Traded item',
                        }),
                        const SizedBox(height: 2),
                        Text(
                          txn.listingTitle.isEmpty
                              ? 'Listing'
                              : txn.listingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rating.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '“${rating.comment}”',
                style: const TextStyle(fontSize: 14.5, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CapsLabel('Flag reason'),
                      const SizedBox(height: 2),
                      Text(
                        reason.isEmpty ? 'No reason given.' : reason,
                        style: const TextStyle(
                          color: AppColors.red,
                          height: 1.35,
                        ),
                      ),
                      Text(
                        'Flagged by ${a.nameOf(widget.report.reportedBy)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _remove(rating),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 19),
                  label: const Text('Remove Review'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _dismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mist,
                    foregroundColor: AppColors.ink,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.done_all, size: 19),
                  label: const Text('Keep & Dismiss'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
