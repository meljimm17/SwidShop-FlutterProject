import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/rating_model.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import 'admin_gate.dart';

/// Flagged-review queue (Phase 4.7).
///
/// Source: `reports` with targetType=='rating' and status=='pending'
/// (targetId = ratingId). Removing a review deletes the doc and refreshes
/// the rated user's average; dismissing clears the queue entry only.
class AdminRatingsScreen extends StatefulWidget {
  const AdminRatingsScreen({super.key});

  @override
  State<AdminRatingsScreen> createState() => _AdminRatingsScreenState();
}

class _AdminRatingsScreenState extends State<AdminRatingsScreen> {
  final _firestore = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: const TopAppBar(title: 'Ratings & Reviews'),
        body: StreamBuilder<List<ReportModel>>(
          stream:
              _firestore.streamReportsByStatus(ReportStatus.pending),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final queue = (snap.data ?? const <ReportModel>[])
                .where((r) => r.targetType == ReportTargetType.rating)
                .toList();
            if (queue.isEmpty) {
              return const Center(
                child: Text(
                  'No flagged reviews.',
                  style: TextStyle(color: AppColors.gray),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: queue.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FlaggedReview(report: queue[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FlaggedReview extends StatefulWidget {
  const _FlaggedReview({required this.report});

  final ReportModel report;

  @override
  State<_FlaggedReview> createState() => _FlaggedReviewState();
}

class _FlaggedReviewState extends State<_FlaggedReview> {
  final _firestore = FirestoreService();
  bool _busy = false;

  ReportModel get _report => widget.report;

  Future<void> _remove(RatingModel rating) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove this review?'),
        content: const Text(
          'The review is deleted and the rated user\'s average is recalculated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _firestore.deleteRating(rating.ratingId);
      await _firestore.refreshUserRating(rating.ratedUserId);
      await _firestore.updateReportStatus(
        _report.reportId,
        ReportStatus.removed,
      );
    } catch (e) {
      debugPrint('removeReview: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _dismiss() async {
    setState(() => _busy = true);
    try {
      await _firestore.updateReportStatus(
        _report.reportId,
        ReportStatus.dismissed,
      );
    } catch (e) {
      debugPrint('dismissFlag: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not dismiss. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RatingModel?>(
      future: _firestore.getRating(_report.targetId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AppCardWrapper(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rating = snap.data;
        if (rating == null) {
          return AppCardWrapper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review already deleted.',
                  style: TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _dismiss,
                  child: const Text('Clear from queue'),
                ),
              ],
            ),
          );
        }
        return AppCardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: UserNameText(
                      rating.raterId,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const Text('→ ', style: TextStyle(color: AppColors.gray)),
                Expanded(
                  child: UserNameText(
                    rating.ratedUserId,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StarRatingDisplay(
                  rating: rating.stars.toDouble(),
                  size: 14,
                ),
              ],
              ),
              if (rating.comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '"${rating.comment}"',
                  style: const TextStyle(height: 1.4),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Flag reason: ${_report.reason.isEmpty ? '—' : _report.reason} · '
                '${_report.createdAt == null ? '' : AppUtils.formatDate(_report.createdAt)}',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.gray),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _dismiss,
                    child: const Text('Keep & Dismiss'),
                  ),
                  FilledButton(
                    onPressed:
                        _busy ? null : () => _remove(rating),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                    ),
                    child: const Text('Remove Review'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
