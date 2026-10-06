import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/chat_message_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import 'transaction_chat_screen.dart';

/// Open deals first, then most recent.
List<TransactionModel> sortThreads(Iterable<TransactionModel> txns) {
  bool open(TransactionModel t) =>
      t.status == TransactionStatus.pending ||
      t.status == TransactionStatus.ongoing ||
      t.status == TransactionStatus.disputed;
  final byId = <String, TransactionModel>{
    for (final t in txns) t.transactionId: t,
  };
  return byId.values.toList()
    ..sort((a, b) {
      final o = (open(a) ? 0 : 1) - (open(b) ? 0 : 1);
      if (o != 0) return o;
      return (b.createdAt ?? DateTime.now())
          .compareTo(a.createdAt ?? DateTime.now());
    });
}

/// One row per deal chat: the OTHER party, Selling/Buying tag, item, last
/// message preview and status. Shared by the seller Messages tab and the
/// customer "My Messages" screen so both list every deal the user is in.
class DealThreadList extends StatelessWidget {
  const DealThreadList({
    super.key,
    required this.threads,
    required this.myUid,
    this.emptyMessage =
        'Buy, sell, win a bid or accept a swap and the deal chat appears here.',
  });

  final List<TransactionModel> threads;
  final String myUid;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No conversations yet',
        message: emptyMessage,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: threads.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 76, color: AppColors.line),
      itemBuilder: (context, i) =>
          _ThreadTile(txn: threads[i], myUid: myUid),
    );
  }
}

class _ThreadTile extends StatefulWidget {
  const _ThreadTile({required this.txn, required this.myUid});

  final TransactionModel txn;
  final String myUid;

  @override
  State<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<_ThreadTile> {
  // Subscribed once per row, not on every rebuild.
  late final Stream<ChatMessageModel?> _last =
      FirestoreService().streamLastMessage(widget.txn.transactionId);

  @override
  Widget build(BuildContext context) {
    final txn = widget.txn;
    final myUid = widget.myUid;
    final selling = txn.sellerId == myUid;
    final otherId = selling ? txn.buyerId : txn.sellerId;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TransactionChatScreen(transactionId: txn.transactionId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserLookup(
                    uid: otherId,
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
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.cream, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListingThumb(
                        url: txn.listingImage,
                        size: 22,
                        radius: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: UserNameText(
                          otherId,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _RoleTag(selling: selling),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    txn.listingTitle.isEmpty ? 'Item' : txn.listingTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
                  ),
                  StreamBuilder<ChatMessageModel?>(
                    stream: _last,
                    builder: (context, snap) {
                      final m = snap.data;
                      if (m == null) return const SizedBox.shrink();
                      final who = m.senderId == myUid ? 'You: ' : '';
                      return Text(
                        '$who${m.hasImage && m.text.isEmpty ? '📷 Photo' : m.preview}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  txn.createdAt == null ? 'now' : timeago.format(txn.createdAt!),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.gray),
                ),
                const SizedBox(height: 4),
                StatusPill.transaction(txn.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.selling});

  final bool selling;

  @override
  Widget build(BuildContext context) {
    final color = selling ? AppColors.teal : AppColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        selling ? 'Selling' : 'Buying',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
