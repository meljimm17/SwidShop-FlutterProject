import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../shared/transaction_chat_screen.dart';

/// Confirms a fixed-price purchase (Phase 3.5).
///
/// No money moves in-app: confirming marks the listing sold, records the
/// deal and opens the chat where buyer and seller arrange payment and
/// delivery themselves.
class BuyNowScreen extends StatefulWidget {
  const BuyNowScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<BuyNowScreen> createState() => _BuyNowScreenState();
}

class _BuyNowScreenState extends State<BuyNowScreen> {
  final _firestore = FirestoreService();
  bool _busy = false;
  String? _txnId;

  Future<void> _confirm(ListingModel listing) async {
    final buyerId = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (buyerId.isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await _firestore.buyNowPurchase(
        listingId: listing.listingId,
        buyerId: buyerId,
      );
      if (!mounted) return;
      setState(() => _txnId = id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Purchase failed. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Buy Now'),
      body: StreamBuilder<ListingModel?>(
        stream: _firestore.streamListing(widget.listingId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final listing = snap.data;
          if (listing == null) {
            return const Center(child: Text('Listing not found'));
          }
          if (_txnId != null) return _confirmation(listing);
          return _summary(listing);
        },
      ),
    );
  }

  Widget _summary(ListingModel listing) {
    final sold = listing.status != ListingStatus.active;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            ListingThumb(
              url: listing.images.isNotEmpty ? listing.images.first : '',
              size: 84,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppUtils.formatCurrency(listing.price),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.coral,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        UserLookup(
          uid: listing.sellerId,
          builder: (context, user) => Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  color: AppColors.gray, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: UserNameText(
                  listing.sellerId,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: const Text(
            'SwidShop never handles payment. After confirming, use the '
            'chat to agree on payment and meet-up or delivery with the '
            'seller.',
            style: TextStyle(height: 1.45, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: 24),
        if (sold)
          const Center(
            child: Text(
              'This item just sold.',
              style: TextStyle(color: AppColors.gray),
            ),
          )
        else
          PrimaryButton(
            label:
                'Confirm Purchase — ${AppUtils.formatCurrency(listing.price)}',
            loading: _busy,
            onPressed: _busy ? null : () => _confirm(listing),
          ),
      ],
    );
  }

  Widget _confirmation(ListingModel listing) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle,
            color: AppColors.green,
            size: 72,
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Purchase placed!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '"${listing.title}" is yours to arrange. '
              'Chat with the seller now to settle payment and delivery.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray, height: 1.45),
            ),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Chat with Seller',
            icon: Icons.chat_bubble_outline,
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    TransactionChatScreen(transactionId: _txnId!),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
