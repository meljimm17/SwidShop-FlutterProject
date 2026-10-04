import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/notification_model.dart';
import '../../models/rating_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

/// Stars + comment form writing one [RatingModel] (Phase 3.10/3.11).
///
/// Shows only when no rating from [raterId] exists yet for [transactionId];
/// callers should also gate on `status == completed`.
class RateSheet extends StatefulWidget {
  const RateSheet({
    super.key,
    required this.transactionId,
    required this.ratedUserId,
    required this.ratedName,
  });

  final String transactionId;
  final String ratedUserId;
  final String ratedName;

  /// True when [raterId] already rated this transaction.
  static Future<bool> alreadyRated(
    String transactionId,
    String raterId,
  ) async {
    try {
      final all = await FirestoreService()
          .ratingsForTransaction(transactionId);
      return all.any((r) => r.raterId == raterId);
    } catch (_) {
      return true; // Fail closed: never offer a duplicate form on error.
    }
  }

  @override
  State<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<RateSheet> {
  double _stars = 5;
  final _commentCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final raterId = auth.firebaseUser?.uid ?? '';
    if (raterId.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      if (await RateSheet.alreadyRated(widget.transactionId, raterId)) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      await FirestoreService().addRating(
        RatingModel(
          ratingId: '',
          raterId: raterId,
          ratedUserId: widget.ratedUserId,
          transactionId: widget.transactionId,
          stars: _stars.round().clamp(1, 5),
          comment: _commentCtrl.text.trim(),
        ),
      );
      // Refresh the visible average right away (trust Cloud Function
      // is not deployed, so nothing else would update it).
      try {
        await FirestoreService().refreshUserRating(widget.ratedUserId);
      } catch (e) {
        debugPrint('refreshUserRating: $e');
      }
      try {
        await FirestoreService().addNotification(
          widget.ratedUserId,
          NotificationModel(
            type: NotificationType.rating,
            message:
                'You received a ${_stars.round()}-star rating from a recent deal.',
            relatedId: 'transaction:${widget.transactionId}',
          ),
        );
      } catch (e) {
        debugPrint('notifyRating: $e');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('addRating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rate ${widget.ratedName.isEmpty ? 'them' : widget.ratedName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            RatingBar.builder(
              initialRating: _stars,
              minRating: 1,
              allowHalfRating: false,
              itemCount: 5,
              itemSize: 40,
              itemPadding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (context, _) => const Icon(
                Icons.star_rounded,
                color: AppColors.amber,
              ),
              onRatingUpdate: (v) => setState(() => _stars = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                hintText: 'How did the deal go?',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
