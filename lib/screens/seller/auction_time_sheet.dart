import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/duration_picker.dart';

/// Opens the "Change end time" sheet for a LIVE auction (works even when it
/// already has bids). Bidders are notified of the change.
Future<void> showChangeAuctionEndSheet(
  BuildContext context,
  ListingModel listing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => _ChangeEndSheet(listing: listing),
  );
}

class _ChangeEndSheet extends StatefulWidget {
  const _ChangeEndSheet({required this.listing});

  final ListingModel listing;

  @override
  State<_ChangeEndSheet> createState() => _ChangeEndSheetState();
}

class _ChangeEndSheetState extends State<_ChangeEndSheet> {
  late DateTime _newEnd = widget.listing.auctionEndAt ?? DateTime.now();
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep "time left" and validation honest while the sheet is open.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _plan =>
      context.read<AuthProvider>().profile?.effectivePlan ?? 'free';

  void _shift(Duration d) => setState(() => _newEnd = _newEnd.add(d));

  Future<void> _setTimeLeft() async {
    final now = DateTime.now();
    final left = _newEnd.difference(now);
    final picked = await showDurationPicker(
      context,
      title: 'Time left',
      helper: 'The auction will end this long from now.',
      initial: left.isNegative ? AppConstants.minAuctionDuration : left,
      min: AppConstants.minAuctionTimeLeft,
      max: AppConstants.maxAuctionDuration(_plan),
    );
    if (picked != null && mounted) {
      setState(() => _newEnd = DateTime.now().add(picked));
    }
  }

  Future<void> _save() async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreService().updateAuctionEnd(
        listingId: widget.listing.listingId,
        sellerId: uid,
        newEnd: _newEnd,
      );
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Auction now ends ${AppUtils.formatDateTime(_newEnd)}. '
            'Bidders were notified.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('updateAuctionEnd: $e');
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Could not change it. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = widget.listing.auctionEndAt;
    final problem = FirestoreService.auctionEndProblem(
      newEnd: _newEnd,
      now: now,
      effectivePlan: _plan,
    );
    final changed = current == null || _newEnd != current;
    final hasBids = (widget.listing.bidCount) > 0 ||
        widget.listing.currentHighestBid != null;

    Widget chip(String label, Duration d) => ActionChip(
          label: Text(label),
          onPressed: _busy ? null : () => _shift(d),
          backgroundColor: AppColors.cream,
          side: const BorderSide(color: AppColors.line),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Change end time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Now ends ${AppUtils.formatDateTime(current)} '
              '(${AppUtils.timeRemaining(current)}).',
              style: const TextStyle(color: AppColors.gray),
            ),
            if (hasBids) ...[
              const SizedBox(height: 6),
              const Text(
                'This auction has bids — everyone who bid will be notified '
                'of the new end time.',
                style: TextStyle(fontSize: 12.5, color: AppColors.amber),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip('− 1 h', const Duration(hours: -1)),
                chip('− 10 min', const Duration(minutes: -10)),
                chip('+ 10 min', const Duration(minutes: 10)),
                chip('+ 1 h', const Duration(hours: 1)),
                chip('+ 1 day', const Duration(days: 1)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _setTimeLeft,
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Set time left…'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (problem == null ? AppColors.teal : AppColors.red)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                problem ??
                    'New end: ${AppUtils.formatDateTime(_newEnd)}\n'
                        '${AppUtils.formatDuration(_newEnd.difference(now))} from now',
                style: TextStyle(
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: problem == null ? AppColors.ink : AppColors.red,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (_busy || problem != null || !changed) ? null : _save,
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
                  : const Text('Save new end time'),
            ),
          ],
        ),
      ),
    );
  }
}
