import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../shared/transaction_chat_screen.dart';

/// The buyer's deal threads (mirror of the seller Messages tab).
/// Open deals first, then newest — all client-side (no indexes).
class BuyerMessagesScreen extends StatelessWidget {
  const BuyerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Messages'),
      body: StreamBuilder<List<TransactionModel>>(
        stream: FirestoreService().streamBuyerTransactions(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final threads = (snap.data ?? const <TransactionModel>[]).toList();
          bool open(TransactionModel t) =>
              t.status == TransactionStatus.pending ||
              t.status == TransactionStatus.ongoing ||
              t.status == TransactionStatus.disputed;
          threads.sort((a, b) {
            final ao = open(a) ? 0 : 1;
            final bo = open(b) ? 0 : 1;
            if (ao != bo) return ao.compareTo(bo);
            final ac = a.createdAt;
            final bc = b.createdAt;
            if (ac == null && bc == null) return 0;
            if (ac == null) return 1;
            if (bc == null) return -1;
            return bc.compareTo(ac);
          });
          if (threads.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              message:
                  'Buy something, win a bid or accept a swap and your deal chats appear here.',
            );
          }
          return ListView.separated(
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
                      uid: t.sellerId,
                      builder: (context, user) => CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.mist,
                        backgroundImage:
                            (user?.photoUrl.isNotEmpty ?? false)
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
                  t.sellerId,
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
          );
        },
      ),
    );
  }
}
