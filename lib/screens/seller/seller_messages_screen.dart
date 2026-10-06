import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/seller_provider.dart';
import '../shared/deal_threads.dart';

/// Messages tab: one conversation per deal, open ones first. Lists the
/// deals you sell AND (for buy-and-sell accounts) the ones you buy.
class SellerMessagesScreen extends StatelessWidget {
  const SellerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seller = context.watch<SellerProvider>();
    final threads = sortThreads([
      ...seller.transactions,
      ...seller.buyingTransactions,
    ]);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        automaticallyImplyLeading: false,
        title: const Text('Messages'),
      ),
      body: seller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : seller.error != null && threads.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load your conversations. Check your '
                  'connection and reopen this tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.gray),
                ),
              ),
            )
          : DealThreadList(
              threads: threads,
              myUid: seller.uid ?? '',
              emptyMessage:
                  'A chat opens for every auction win, purchase or '
                  'accepted swap.',
            ),
    );
  }
}
