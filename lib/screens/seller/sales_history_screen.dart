import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/monthly_bars.dart';
import '../shared/transaction_chat_screen.dart';
import 'fee_payments.dart';

/// Completed sales across Buy Now, Auction wins and Swaps. The header
/// totals always match the rows currently shown; each row opens the chat.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  ListingType? _filter;

  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SellerProvider>();
    final all = s.completedSales;
    final rows = all
        .where((t) => _filter == null || t.type == _filter)
        .toList();
    final total = rows.fold<double>(0, (sum, t) => sum + t.amount);
    final disputed = s.transactions
        .where((t) => t.status == TransactionStatus.disputed)
        .length;
    int count(ListingType t) => all.where((x) => x.type == t).length;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        title: const Text(
          'Sales History',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ),
      body: s.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _summary(s, total, rows.length, disputed),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _pill('All Types', all.length, null, null),
                      _pill(
                        'Buy Now',
                        count(ListingType.buyNow),
                        ListingType.buyNow,
                        AppColors.coral,
                      ),
                      _pill(
                        'Auction Wins',
                        count(ListingType.bid),
                        ListingType.bid,
                        AppColors.amber,
                      ),
                      _pill(
                        'Swaps',
                        count(ListingType.swap),
                        ListingType.swap,
                        AppColors.teal,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Recent Settlements',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No completed sales',
                      message:
                          'Deals appear here once they are marked '
                          'completed in the chat.',
                    ),
                  )
                else
                  for (final t in rows) ...[
                    _SettlementCard(txn: t),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
    );
  }

  Widget _summary(SellerProvider s, double total, int count, int disputed) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_outlined, size: 18, color: AppColors.teal),
              SizedBox(width: 6),
              Text(
                'TOTAL SETTLED',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppUtils.formatCurrency(total),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    Text(
                      'across $count completed transaction'
                      '${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF55534E),
                      ),
                    ),
                  ],
                ),
              ),
              // Six-month trend of settled totals (all types).
              SizedBox(
                width: 84,
                child: MonthlyBars(
                  data: SellerStats.monthlySettled(s.transactions),
                  height: 44,
                  showLabels: false,
                  interactive: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Icon(
                  disputed == 0
                      ? Icons.thumb_up_alt_outlined
                      : Icons.report_gmailerrorred_outlined,
                  size: 17,
                  color: disputed == 0 ? AppColors.green : AppColors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    disputed == 0
                        ? (count == 0
                              ? 'No disputes so far'
                              : 'All $count deal${count == 1 ? '' : 's'} '
                                    'completed with no disputes')
                        : '$disputed deal${disputed == 1 ? '' : 's'} in '
                              'dispute — check Orders',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, int count, ListingType? type, Color? dot) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Icon(Icons.circle, size: 8, color: dot),
                const SizedBox(width: 6),
              ],
              Text(
                '$label ($count)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.txn});

  final TransactionModel txn;

  @override
  Widget build(BuildContext context) {
    final t = txn;
    final (String tag, Color color) = switch (t.type) {
      ListingType.buyNow => ('BUY NOW', AppColors.coral),
      ListingType.bid => ('AUCTION', AppColors.amber),
      ListingType.swap => ('SWAP', AppColors.teal),
    };
    final title = t.type == ListingType.swap && t.swapItemTitle.isNotEmpty
        ? '${t.listingTitle} ⇄ ${t.swapItemTitle}'
        : (t.listingTitle.isEmpty ? 'Item' : t.listingTitle);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                TransactionChatScreen(transactionId: t.transactionId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  UserLookup(
                    uid: t.buyerId,
                    builder: (context, user) => CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.mist,
                      backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                          ? NetworkImage(user!.photoUrl)
                          : null,
                      child: (user?.photoUrl.isNotEmpty ?? false)
                          ? null
                          : const Icon(
                              Icons.person_outline,
                              size: 16,
                              color: AppColors.gray,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: UserNameText(
                      t.buyerId,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: color == AppColors.amber
                            ? const Color(0xFF8A5A0B)
                            : color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    t.createdAt == null
                        ? ''
                        : DateFormat('MMM d • h:mm a').format(t.createdAt!),
                    style: const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ListingThumb(url: t.listingImage, size: 80, radius: 14),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (t.type == ListingType.swap && t.amount == 0)
                          const Text(
                            'Item-for-item swap',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.gray,
                            ),
                          )
                        else
                          Text.rich(
                            TextSpan(
                              text: AppUtils.formatCurrency(t.amount),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                              children: [
                                TextSpan(
                                  text: t.type == ListingType.bid
                                      ? '  hammer price'
                                      : '  sold',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.gray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 13,
                                color: AppColors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t.type == ListingType.swap
                                    ? 'Swap completed'
                                    : 'Completed',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (t.feeStatus != 'none') ...[
                          const SizedBox(height: 6),
                          _feeLine(context, t),
                        ],
                      ],
                    ),
                  ),
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.cream,
                    child: Icon(Icons.chevron_right, color: AppColors.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Platform fee 5%: ₱50 · Unpaid, due Oct 12" (+ inline Pay Now).
  Widget _feeLine(BuildContext context, TransactionModel t) {
    final state = t.feeStatus == 'paid'
        ? 'Paid'
        : t.feeStatus == 'void'
            ? 'Void'
            : t.feeOverdue
                ? 'Overdue'
                : 'Unpaid${t.feeDueAt == null ? '' : ', due ${AppUtils.formatDate(t.feeDueAt)}'}';
    final color = t.feeStatus == 'paid'
        ? AppColors.green
        : t.feeOverdue
            ? AppColors.red
            : AppColors.amber;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Platform fee ${(t.feeRate * 100).toStringAsFixed(0)}%: '
            '${AppUtils.formatCurrency(t.feeAmount)} · $state',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (t.feeUnpaid)
          TextButton(
            onPressed: () => payOneFee(context, t),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Pay Now'),
          ),
      ],
    );
  }
}
