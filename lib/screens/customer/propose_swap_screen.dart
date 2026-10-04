import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/swap_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';

/// Offers one of the customer's own listings for a swap target (Phase 3.7).
class ProposeSwapScreen extends StatefulWidget {
  const ProposeSwapScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ProposeSwapScreen> createState() => _ProposeSwapScreenState();
}

class _ProposeSwapScreenState extends State<ProposeSwapScreen> {
  final _firestore = FirestoreService();
  final _messageCtrl = TextEditingController();
  String? _offeredItemId;
  bool _busy = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _propose(ListingModel target) async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty || _offeredItemId == null) return;
    setState(() => _busy = true);
    try {
      final offerId = await _firestore.createSwapOffer(
        SwapOfferModel(
          offerId: '',
          listingId: target.listingId,
          offeredById: uid,
          offeredItemId: _offeredItemId!,
          message: _messageCtrl.text.trim(),
        ),
      );
      if (target.sellerId.isNotEmpty) {
        try {
          await _firestore.addNotification(
            target.sellerId,
            NotificationModel(
              type: NotificationType.swapOffer,
              message: 'New swap offer on "${target.title}".',
              relatedId: 'offer:$offerId',
            ),
          );
        } catch (e) {
          debugPrint('notifySwapOffer: $e');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Swap proposed — the seller has been notified.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Could not propose. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final canSell =
        context.select<AuthProvider, bool>((a) => a.profile?.role.canSell ?? false);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Propose Swap'),
      body: StreamBuilder<ListingModel?>(
        stream: _firestore.streamListing(widget.listingId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final target = snap.data;
          if (target == null) {
            return const Center(child: Text('Listing not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'You want',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              _targetCard(target),
              const SizedBox(height: 20),
              if (target.sellerId == uid)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'This is your listing — you cannot swap with yourself.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray),
                    ),
                  ),
                )
              else ...[
                const Text(
                  'You offer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.gray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                if (!canSell)
                  const Text(
                    'Only seller accounts can offer items. '
                    'Switch to a seller account to swap.',
                    style: TextStyle(color: AppColors.gray, height: 1.45),
                  )
                else
                  StreamBuilder<List<ListingModel>>(
                    stream: _firestore.streamSellerListings(uid),
                    builder: (context, mineSnap) {
                      final mine = (mineSnap.data ?? const <ListingModel>[])
                          .where((l) =>
                              l.status == ListingStatus.active &&
                              l.listingId != target.listingId)
                          .toList();
                      if (mineSnap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (mine.isEmpty) {
                        return const Text(
                          'You have no other active listings to offer. '
                          'Post one first, then come back.',
                          style: TextStyle(
                              color: AppColors.gray, height: 1.45),
                        );
                      }
                      return Column(
                        children: [
                          for (final m in mine) _offerTile(m, target),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message to seller (optional)',
                    hintText: 'e.g. meet-up only, size details…',
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Propose Swap',
                  icon: Icons.swap_horiz,
                  loading: _busy,
                  onPressed: (_busy || _offeredItemId == null || !canSell)
                      ? null
                      : () => _propose(target),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _targetCard(ListingModel target) {
    return AppCardWrapper(
      child: Row(
        children: [
          ListingThumb(
            url: target.images.isNotEmpty ? target.images.first : '',
            size: 64,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TypeBadge(target.type),
                    const SizedBox(width: 8),
                    if (!target.swapOnly && target.price != null)
                      Text(
                        AppUtils.formatCurrency(target.price),
                        style: const TextStyle(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      const Text(
                        'Trade only',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerTile(ListingModel m, ListingModel target) {
    final selected = _offeredItemId == m.listingId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        onTap: _busy
            ? null
            : () => setState(() => _offeredItemId = m.listingId),
        child: Row(
          children: [
            ListingThumb(
              url: m.images.isNotEmpty ? m.images.first : '',
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TypeBadge(m.type),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.teal : AppColors.gray,
            ),
          ],
        ),
      ),
    );
  }
}
