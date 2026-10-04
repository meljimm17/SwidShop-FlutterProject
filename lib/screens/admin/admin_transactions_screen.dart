import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/chat_message_model.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../shared/transaction_chat_screen.dart';
import 'admin_charts.dart';
import 'admin_gate.dart';

/// Oversee every deal, including disputes (Phase 4.4).
///
/// No escrow exists anywhere in SwidShop: "settled volume" is the sum of
/// completed deal amounts, and "clean rate" is completed ÷ resolved deals.
/// Disputed threads open read-only for review (full chat via the shared
/// screen, which both parties also use).
class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  State<AdminTransactionsScreen> createState() =>
      _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  final _firestore = FirestoreService();
  ListingType? _type;
  TransactionStatus? _status;
  int _visible = 25;

  static const _page = 25;

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: const TopAppBar(title: 'Transactions'),
        body: StreamBuilder<List<TransactionModel>>(
          stream: _firestore.streamAllTransactions(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            var txns = snap.data ?? const <TransactionModel>[];
            if (_type != null) {
              txns = txns.where((t) => t.type == _type).toList();
            }
            if (_status != null) {
              txns = txns.where((t) => t.status == _status).toList();
            }
            // Disputed first, then newest.
            txns.sort((a, b) {
              final ad =
                  a.status == TransactionStatus.disputed ? 0 : 1;
              final bd =
                  b.status == TransactionStatus.disputed ? 0 : 1;
              if (ad != bd) return ad.compareTo(bd);
              final ac = a.createdAt;
              final bc = b.createdAt;
              if (ac == null && bc == null) return 0;
              if (ac == null) return 1;
              if (bc == null) return -1;
              return bc.compareTo(ac);
            });
            final shown = txns.take(_visible).toList();
            return Column(
              children: [
                _summary(txns),
                _chips(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Showing ${shown.length} of ${txns.length} audited',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(
                          child: Text(
                            'No transactions match.',
                            style: TextStyle(color: AppColors.gray),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: shown.length +
                              (txns.length > _visible ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= shown.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _visible += _page,
                                  ),
                                  child: Text(
                                    'Load more (${txns.length - _visible} left)',
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: _row(shown[i]),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(List<TransactionModel> all) {
    var settled = 0.0;
    var completed = 0;
    var resolved = 0;
    for (final t in all) {
      switch (t.status) {
        case TransactionStatus.completed:
          completed++;
          resolved++;
          if (t.type != ListingType.swap) settled += t.amount;
        case TransactionStatus.cancelled:
        case TransactionStatus.disputed:
          resolved++;
        case TransactionStatus.pending:
        case TransactionStatus.ongoing:
          break;
      }
    }
    final cleanRate =
        resolved == 0 ? null : (completed / resolved * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              label: 'Settled volume',
              value: AppUtils.formatCurrency(settled),
              icon: Icons.payments_outlined,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'Clean rate',
              value: cleanRate == null ? '—' : '$cleanRate%',
              icon: Icons.verified_outlined,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.coral,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.coral : AppColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    void reset() => setState(() => _visible = _page);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              chip('All types', _type == null, () {
                setState(() => _type = null);
                reset();
              }),
              chip('Buy Now', _type == ListingType.buyNow, () {
                setState(() => _type = ListingType.buyNow);
                reset();
              }),
              chip('Bidding', _type == ListingType.bid, () {
                setState(() => _type = ListingType.bid);
                reset();
              }),
              chip('Swap', _type == ListingType.swap, () {
                setState(() => _type = ListingType.swap);
                reset();
              }),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            children: [
              chip('Any status', _status == null, () {
                setState(() => _status = null);
                reset();
              }),
              for (final s in TransactionStatus.values)
                chip(s.value, _status == s, () {
                  setState(() => _status = _status == s ? null : s);
                  reset();
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(TransactionModel txn) {
    final disputed = txn.status == TransactionStatus.disputed;
    return AppCardWrapper(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: ListingThumb(url: txn.listingImage, size: 48),
        title: Text(
          txn.listingTitle.isEmpty ? txn.orderNumber : txn.listingTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            TypeBadge(txn.type),
            const SizedBox(width: 6),
            StatusPill.transaction(txn.status),
          ],
        ),
        trailing: Text(
          txn.type == ListingType.swap
              ? 'Swap'
              : AppUtils.formatCurrency(txn.amount),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: UserNameText(
                  txn.buyerId,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ),
              const Text(' → ', style: TextStyle(color: AppColors.gray)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: UserNameText(
                    txn.sellerId,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _threadPreview(txn.transactionId),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransactionChatScreen(
                    transactionId: txn.transactionId,
                  ),
                ),
              ),
              child: Text(
                disputed ? 'Review full dispute thread' : 'Open thread',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-only message preview for investigation.
  Widget _threadPreview(String transactionId) {
    return StreamBuilder<List<ChatMessageModel>>(
      stream: _firestore.streamMessages(transactionId),
      builder: (context, snap) {
        final msgs = snap.data ?? const <ChatMessageModel>[];
        if (msgs.isEmpty) {
          return const Text(
            'No messages yet.',
            style: TextStyle(fontSize: 12, color: AppColors.gray),
          );
        }
        final last = msgs.last;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${msgs.length} message${msgs.length == 1 ? '' : 's'} · latest: "${last.text}"',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        );
      },
    );
  }
}
