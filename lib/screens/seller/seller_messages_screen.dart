import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/transaction_model.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/listing_widgets.dart';
import '../shared/transaction_chat_screen.dart';

/// Messages tab: one conversation per deal, open ones first.
class SellerMessagesScreen extends StatelessWidget {
  const SellerMessagesScreen({super.key});

  static bool _isOpen(TransactionModel t) =>
      t.status == TransactionStatus.pending ||
      t.status == TransactionStatus.ongoing ||
      t.status == TransactionStatus.disputed;

  @override
  Widget build(BuildContext context) {
    final seller = context.watch<SellerProvider>();
    final threads = [...seller.transactions]
      ..sort((a, b) {
        final open = (_isOpen(a) ? 0 : 1) - (_isOpen(b) ? 0 : 1);
        if (open != 0) return open;
        return (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        );
      });

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        automaticallyImplyLeading: false,
        title: const Text('Messages'),
      ),
      body: seller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : threads.isEmpty
          ? const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              message:
                  'A chat opens with the buyer for every auction '
                  'win, accepted swap or purchase.',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: threads.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 76, color: AppColors.line),
              itemBuilder: (context, i) {
                final t = threads[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TransactionChatScreen(transactionId: t.transactionId),
                    ),
                  ),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserLookup(
                        uid: t.buyerId,
                        builder: (context, user) => CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.mist,
                          backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                              ? NetworkImage(user!.photoUrl)
                              : null,
                          child: (user?.photoUrl.isNotEmpty ?? false)
                              ? null
                              : const Icon(
                                  Icons.person_outline,
                                  color: AppColors.gray,
                                ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.cream,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListingThumb(
                            url: t.listingImage,
                            size: 22,
                            radius: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: UserNameText(
                    t.buyerId,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    t.listingTitle.isEmpty ? 'Item' : t.listingTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        t.createdAt == null
                            ? 'now'
                            : timeago.format(t.createdAt!),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.gray,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatusPill.transaction(t.status),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
