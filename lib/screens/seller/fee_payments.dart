import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../shared/demo_gcash_screen.dart';

/// Unpaid platform fees among [txns] (cancelled deals never owe one).
List<TransactionModel> unpaidFees(Iterable<TransactionModel> txns) => txns
    .where((t) => t.feeUnpaid && t.status != TransactionStatus.cancelled)
    .toList();

/// Pays ONE platform fee through the demo GCash flow. True when paid.
Future<bool> payOneFee(BuildContext context, TransactionModel txn) async {
  final ref = await runDemoPayment(
    context,
    itemLabel:
        'Platform fee · ${txn.listingTitle.isEmpty ? txn.orderNumber : txn.listingTitle}',
    amount: txn.feeAmount,
    apply: (ref) => FirestoreService().payFee(
      transactionId: txn.transactionId,
      sellerId: txn.sellerId,
      referenceNo: ref,
    ),
  );
  if (ref != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fee paid.')),
    );
  }
  return ref != null;
}

/// Pays exactly the fees in [unpaid] (what the banner showed) in one demo
/// flow. Returns how many were paid (0 = cancelled).
Future<int> payAllFees(
  BuildContext context,
  List<TransactionModel> unpaid,
) async {
  if (unpaid.isEmpty) return 0;
  var total = 0.0;
  for (final t in unpaid) {
    total += t.feeAmount;
  }
  var paid = 0;
  final ref = await runDemoPayment(
    context,
    itemLabel: unpaid.length == 1
        ? 'Platform fee · ${unpaid.first.listingTitle}'
        : 'All unpaid platform fees (${unpaid.length})',
    amount: total,
    apply: (ref) async {
      paid = await FirestoreService().payFees(
        sellerId: unpaid.first.sellerId,
        transactionIds: [for (final t in unpaid) t.transactionId],
        referenceNo: ref,
      );
    },
  );
  if (ref != null && context.mounted && paid > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Paid $paid fee${paid == 1 ? '' : 's'} .')),
    );
  }
  return ref == null ? 0 : paid;
}

/// Alert banner for the Seller Centre: total unpaid, nearest due date,
/// Pay Now (all). Renders nothing when nothing is owed.
class FeeAlertBanner extends StatelessWidget {
  const FeeAlertBanner({super.key, required this.unpaid});

  /// Unpaid-fee transactions (see [unpaidFees]).
  final List<TransactionModel> unpaid;

  @override
  Widget build(BuildContext context) {
    if (unpaid.isEmpty) return const SizedBox.shrink();
    var total = 0.0;
    DateTime? nearest;
    for (final t in unpaid) {
      total += t.feeAmount;
      if (t.feeDueAt != null &&
          (nearest == null || t.feeDueAt!.isBefore(nearest))) {
        nearest = t.feeDueAt;
      }
    }
    final overdue = unpaid.any((t) => t.feeOverdue);
    final tone = overdue ? AppColors.red : AppColors.amber;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: tone, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overdue ? 'Overdue platform fees' : 'Unpaid platform fees',
                  style: TextStyle(fontWeight: FontWeight.w800, color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${AppUtils.formatCurrency(total)} across ${unpaid.length} '
            'deal${unpaid.length == 1 ? '' : 's'}'
            '${nearest == null ? '' : ' · ${overdue ? 'due since' : 'nearest due'} ${AppUtils.formatDate(nearest)}'}',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => payAllFees(context, unpaid),
              style: FilledButton.styleFrom(backgroundColor: tone),
              child: const Text('Pay Now'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Red hold banner: why the shop is restricted. Shown whenever the
/// account is on hold (automatic fee hold or an admin's manual hold).
class FeeHoldBanner extends StatelessWidget {
  const FeeHoldBanner({
    super.key,
    required this.onHold,
    required this.manual,
    required this.unpaid,
  });

  final bool onHold;

  /// True when an admin placed the hold (paying does not lift it).
  final bool manual;
  final List<TransactionModel> unpaid;

  @override
  Widget build(BuildContext context) {
    if (!onHold) return const SizedBox.shrink();
    var overdueTotal = 0.0;
    for (final t in unpaid) {
      if (t.feeOverdue) overdueTotal += t.feeAmount;
    }
    final why = overdueTotal > 0
        ? '${AppUtils.formatCurrency(overdueTotal)} in platform fees is overdue.'
        : manual
            ? 'An admin placed a hold on your shop.'
            : 'Your shop has an unpaid-fee hold.';
    final lift = manual
        ? 'Contact SwidShop support to have it lifted.'
        : 'Pay the overdue fees below to lift it right away.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pause_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your shop is ON HOLD',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$why You can still log in, chat and pay, but you cannot post '
            'new listings or accept swaps, and your listings are hidden '
            'from customers. $lift',
            style: const TextStyle(color: Colors.white, height: 1.45),
          ),
        ],
      ),
    );
  }
}
