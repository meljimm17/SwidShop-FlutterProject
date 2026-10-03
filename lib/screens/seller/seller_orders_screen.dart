import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/type_badge.dart';
import '../shared/transaction_chat_screen.dart';
import 'sales_history_screen.dart';

/// Orders tab: deals still being arranged (pending / in progress /
/// disputed). Completed ones live in Sales history.
class SellerOrdersScreen extends StatelessWidget {
  const SellerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seller = context.watch<SellerProvider>();
    final orders = seller.openOrders;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        automaticallyImplyLeading: false,
        title: const Text('Orders'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
            ),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Sales history'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: seller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No open orders',
              message:
                  'Auction wins, accepted swaps and purchases show '
                  'here until they are completed.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => OrderCard(txn: orders[i]),
            ),
    );
  }
}

/// Compact order card (order no., status, item, buyer, amount) → chat.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.txn});

  final TransactionModel txn;

  @override
  Widget build(BuildContext context) {
    return OutlineCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TransactionChatScreen(transactionId: txn.transactionId),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(switch (txn.type) {
              ListingType.bid => Icons.gavel_rounded,
              ListingType.swap => Icons.swap_horiz_rounded,
              ListingType.buyNow => Icons.shopping_bag_outlined,
            }, color: AppColors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Order #${txn.orderNumber}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill.transaction(txn.status),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    txn.listingTitle.isEmpty ? 'Item' : txn.listingTitle,
                    if (txn.type != ListingType.swap)
                      AppUtils.formatCurrency(txn.amount),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TypeBadge(txn.type),
                    const SizedBox(width: 8),
                    const Text(
                      'with ',
                      style: TextStyle(fontSize: 12, color: AppColors.gray),
                    ),
                    Flexible(
                      child: UserNameText(
                        txn.buyerId,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.gray),
        ],
      ),
    );
  }
}
