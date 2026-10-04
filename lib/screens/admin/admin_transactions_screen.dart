import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/admin_provider.dart';
import '../shared/transaction_chat_screen.dart';
import 'admin_widgets.dart';

/// Date windows for the Orders filter.
enum _Range {
  week('Last 7 Days', 7),
  month('Last 30 Days', 30),
  all('All Time', null);

  const _Range(this.label, this.days);

  final String label;
  final int? days;
}

/// Orders tab: every deal on the marketplace, disputes first (Phase 4.4).
///
/// SwidShop never holds money — there is no escrow. "Settled" is the sum of
/// completed cash deals; "clean rate" is completed ÷ closed deals.
class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  State<AdminTransactionsScreen> createState() =>
      _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  ListingType? _type;
  TransactionStatus? _status;
  _Range _range = _Range.month;
  int _visible = 20;

  static const _page = 20;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final all = a.transactions;
    final now = DateTime.now();

    var inRange = all;
    if (_range.days != null) {
      final since = now.subtract(Duration(days: _range.days!));
      inRange = all.where((t) => (t.createdAt ?? now).isAfter(since)).toList();
    }
    final typeCounts = {
      for (final t in ListingType.values)
        t: inRange.where((x) => x.type == t).length,
    };
    var txns = inRange;
    if (_type != null) txns = txns.where((t) => t.type == _type).toList();
    if (_status != null) txns = txns.where((t) => t.status == _status).toList();
    txns = [
      ...txns.where((t) => t.status == TransactionStatus.disputed),
      ...txns.where((t) => t.status != TransactionStatus.disputed),
    ];
    final shown = txns.take(_visible).toList();
    final clean = AdminStats.cleanRate(inRange);
    final disputes = inRange
        .where((t) => t.status == TransactionStatus.disputed)
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${AppUtils.formatCurrency(AdminStats.settledVolume(inRange))} settled'
                  ' · ${clean == null ? '—' : '$clean%'} clean'
                  ' · $disputes dispute${disputes == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ),
              Tooltip(
                message: 'Deals are arranged directly in chat. SwidShop never holds payments.',
                triggerMode: TooltipTriggerMode.tap,
                child: const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
        ),
        PillRow<ListingType?>(
          selected: _type,
          onSelected: (t) => setState(() {
            _type = t;
            _visible = _page;
          }),
          options: [
            PillOption(null, 'All Types (${inRange.length})'),
            PillOption(
              ListingType.buyNow,
              'Buy Now (${typeCounts[ListingType.buyNow]})',
            ),
            PillOption(
              ListingType.bid,
              'Bidding (${typeCounts[ListingType.bid]})',
            ),
            PillOption(
              ListingType.swap,
              'Swap (${typeCounts[ListingType.swap]})',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _DropChip<_Range>(
                  icon: Icons.calendar_today_outlined,
                  label: _range.label,
                  values: [for (final r in _Range.values) (r, r.label)],
                  onSelected: (r) => setState(() {
                    _range = r;
                    _visible = _page;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropChip<TransactionStatus?>(
                  icon: Icons.tune,
                  label: _status == null
                      ? 'All Statuses'
                      : txnStatusLabel(_status!),
                  values: [
                    (null, 'All Statuses'),
                    for (final s in TransactionStatus.values)
                      (s, txnStatusLabel(s)),
                  ],
                  onSelected: (s) => setState(() {
                    _status = s;
                    _visible = _page;
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No transactions match.',
                style: TextStyle(color: AppColors.gray),
              ),
            ),
          ),
        for (final t in shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _TxnCard(txn: t),
          ),
        if (txns.length > _visible)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _visible += _page),
              child: Text('Load more (${txns.length - _visible} left)'),
            ),
          ),
        const SizedBox(height: 8),
        const Icon(Icons.verified_outlined, color: AppColors.gray),
        const SizedBox(height: 6),
        Text(
          'Showing ${shown.length} of ${txns.length} transaction${txns.length == 1 ? '' : 's'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const Text(
          'SwidShop direct-deal log',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.gray),
        ),
      ],
    );
  }
}

class _DropChip<T> extends StatelessWidget {
  const _DropChip({
    required this.icon,
    required this.label,
    required this.values,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<(T, String)> values;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      color: AppColors.surface,
      position: PopupMenuPosition.under,
      onSelected: (i) => onSelected(values[i].$1),
      itemBuilder: (_) => [
        for (var i = 0; i < values.length; i++)
          PopupMenuItem(value: i, child: Text(values[i].$2)),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}

class _TxnCard extends StatelessWidget {
  const _TxnCard({required this.txn});

  final TransactionModel txn;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionChatScreen(transactionId: txn.transactionId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final t = txn;
    final cancelled = t.status == TransactionStatus.cancelled;
    final swap = t.type == ListingType.swap;
    final typePill = switch (t.type) {
      ListingType.buyNow => const SoftPill('Buy Now', color: AppColors.coral),
      ListingType.bid => const SoftPill(
        'Bidding Won',
        color: Color(0xFF9A6200),
        icon: Icons.gavel,
        solid: true,
      ),
      ListingType.swap => const SoftPill(
        'Item Swap',
        color: AppColors.teal,
        solid: true,
      ),
    };

    return AdminCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${t.orderNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (t.createdAt != null)
                Expanded(
                  child: Text(
                    '  •  ${DateFormat('MMM d, h:mm a').format(t.createdAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                )
              else
                const Spacer(),
              typePill,
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: cancelled ? 0.6 : 1,
                child: TaggedThumb(
                  url: t.listingImage,
                  width: 72,
                  height: 72,
                  radius: 8,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.listingTitle.isEmpty ? 'Listing' : t.listingTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.nameOf(t.buyerId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: swap ? AppColors.teal : AppColors.ink,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            cancelled
                                ? Icons.cancel_outlined
                                : swap
                                ? Icons.swap_horiz
                                : Icons.arrow_forward,
                            size: 15,
                            color: cancelled ? AppColors.red : AppColors.coral,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            a.nameOf(t.sellerId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: swap ? AppColors.teal : AppColors.ink,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (swap)
                      Text(
                        t.swapItemTitle.isEmpty
                            ? 'Item-for-item trade'
                            : 'For: ${t.swapItemTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.gray,
                        ),
                      )
                    else
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            AppUtils.formatCurrency(t.amount),
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: cancelled
                                  ? AppColors.gray
                                  : AppColors.coralDeep,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (cancelled)
                            const Text(
                              'Deal Cancelled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statusPanel(context),
        ],
      ),
    );
  }

  Widget _statusPanel(BuildContext context) {
    final (icon, title, body, color) = switch (txn.status) {
      TransactionStatus.disputed => (
        Icons.gavel,
        'DISPUTED',
        'A party flagged a problem with this deal. Review the chat thread.',
        AppColors.red,
      ),
      TransactionStatus.pending => (
        Icons.hourglass_top,
        'PENDING',
        'Waiting for the seller to start the deal in chat.',
        AppColors.amber,
      ),
      TransactionStatus.ongoing => (
        Icons.handshake_outlined,
        'IN PROGRESS',
        'Buyer and seller are arranging meetup or delivery in chat.',
        AppColors.amber,
      ),
      TransactionStatus.completed => (
        Icons.check_circle_outline,
        '',
        'Agreed in chat & completed',
        AppColors.green,
      ),
      TransactionStatus.cancelled => (
        Icons.error_outline,
        'CANCELLED',
        'This deal was called off before completion.',
        AppColors.gray,
      ),
    };
    final dark = color == AppColors.amber ? const Color(0xFF8A5200) : color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
          ),
          child: title.isEmpty
              ? Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: dark, fontWeight: FontWeight.w600),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: dark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: dark,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            body,
                            style: TextStyle(color: dark, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        if (txn.status == TransactionStatus.disputed) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _open(context),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.mist,
              foregroundColor: AppColors.coralDeep,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Inspect full dispute & chat thread →',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}
