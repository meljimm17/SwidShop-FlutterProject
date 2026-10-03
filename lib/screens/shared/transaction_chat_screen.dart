import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/chat_message_model.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/type_badge.dart';

/// Chat & Status for one transaction: deal header with status controls and
/// the `chats/{transactionId}/messages` thread.
///
/// Basic version shared by seller screens; the full Phase 3.8 screen builds
/// on this.
class TransactionChatScreen extends StatefulWidget {
  const TransactionChatScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  State<TransactionChatScreen> createState() => _TransactionChatScreenState();
}

class _TransactionChatScreenState extends State<TransactionChatScreen> {
  final _firestore = FirestoreService();
  final _textCtrl = TextEditingController();
  late final Stream<TransactionModel?> _txn =
      _firestore.streamTransaction(widget.transactionId);
  late final Stream<List<ChatMessageModel>> _messages =
      _firestore.streamMessages(widget.transactionId);
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String uid) async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _firestore.sendMessage(
        widget.transactionId,
        ChatMessageModel(senderId: uid, text: text),
      );
      _textCtrl.clear();
    } catch (e) {
      debugPrint('sendMessage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message not sent. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(TransactionStatus status, String confirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _firestore.updateTransactionStatus(widget.transactionId, status);
    } catch (e) {
      debugPrint('updateTransactionStatus: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';

    return StreamBuilder<TransactionModel?>(
      stream: _txn,
      builder: (context, snap) {
        final txn = snap.data;
        final otherId =
            txn == null ? '' : (txn.sellerId == uid ? txn.buyerId : txn.sellerId);
        return Scaffold(
          backgroundColor: AppColors.cream,
          appBar: AppBar(
            backgroundColor: AppColors.cream,
            titleSpacing: 0,
            title: txn == null
                ? const Text('Chat')
                : Row(
                    children: [
                      UserLookup(
                        uid: otherId,
                        builder: (context, user) => CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.mist,
                          backgroundImage:
                              (user?.photoUrl.isNotEmpty ?? false)
                                  ? NetworkImage(user!.photoUrl)
                                  : null,
                          child: (user?.photoUrl.isNotEmpty ?? false)
                              ? null
                              : const Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: AppColors.gray,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserNameText(
                              otherId,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              txn.sellerId == uid ? 'Buyer' : 'Seller',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (txn != null) _dealHeader(txn, uid),
                Expanded(child: _thread(uid)),
                _composer(uid, enabled: txn != null),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dealHeader(TransactionModel txn, String uid) {
    final isSeller = txn.sellerId == uid;
    final open = txn.status == TransactionStatus.pending ||
        txn.status == TransactionStatus.ongoing;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ListingThumb(url: txn.listingImage, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.listingTitle.isEmpty ? 'Item' : txn.listingTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        TypeBadge(txn.type),
                        const SizedBox(width: 8),
                        StatusPill.transaction(txn.status),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                txn.type == ListingType.swap
                    ? 'Swap'
                    : AppUtils.formatCurrency(txn.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.coral,
                ),
              ),
            ],
          ),
          if (open) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (isSeller && txn.status == TransactionStatus.pending)
                  _action(
                    'Start deal',
                    AppColors.teal,
                    () => _setStatus(
                      TransactionStatus.ongoing,
                      'Mark this deal as in progress?',
                    ),
                  ),
                if (isSeller) ...[
                  _action(
                    'Mark completed',
                    AppColors.green,
                    () => _setStatus(
                      TransactionStatus.completed,
                      'Mark as completed? Only do this once the item and '
                          'payment (or swap item) were handed over.',
                    ),
                  ),
                ],
                _action(
                  'Cancel',
                  AppColors.red,
                  () => _setStatus(
                    TransactionStatus.cancelled,
                    'Cancel this deal?',
                  ),
                  outlined: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _action(
    String label,
    Color color,
    VoidCallback onTap, {
    bool outlined = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: outlined
            ? OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              )
            : FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              ),
      ),
    );
  }

  Widget _thread(String uid) {
    return StreamBuilder<List<ChatMessageModel>>(
      stream: _messages,
      builder: (context, snap) {
        final msgs = snap.data ?? const <ChatMessageModel>[];
        if (snap.connectionState == ConnectionState.waiting && msgs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (msgs.isEmpty) {
          return const EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'Start the conversation',
            message: 'Agree on payment and meet-up or courier details here.',
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final m = msgs[msgs.length - 1 - i];
            final mine = m.senderId == uid;
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                ),
                decoration: BoxDecoration(
                  color: mine ? AppColors.coral : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  border: mine ? null : Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      m.text,
                      style: TextStyle(
                        color: mine ? Colors.white : AppColors.ink,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      m.timestamp == null
                          ? 'Sending…'
                          : AppUtils.formatDateTime(m.timestamp),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: mine ? Colors.white70 : AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _composer(String uid, {required bool enabled}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message'),
              onSubmitted: (_) => _send(uid),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: enabled && !_sending ? () => _send(uid) : null,
            style: IconButton.styleFrom(backgroundColor: AppColors.coral),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
