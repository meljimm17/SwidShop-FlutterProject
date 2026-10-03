import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/swap_offer_model.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/star_rating_display.dart';
import 'swap_offer_actions.dart';

/// Incoming pending swap offers on the seller's listings.
///
/// Accept → offer accepted, all other pending offers on that listing
/// declined, listing sold, `swap` transaction created, chat opened.
/// Decline → offer declined only.
class SwapOffersScreen extends StatefulWidget {
  const SwapOffersScreen({super.key});

  @override
  State<SwapOffersScreen> createState() => _SwapOffersScreenState();
}

class _SwapOffersScreenState extends State<SwapOffersScreen> {
  final _firestore = FirestoreService();
  final Map<String, Future<ListingModel?>> _offeredItems = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  Future<ListingModel?> _offeredItem(String id) =>
      _offeredItems.putIfAbsent(id, () => _firestore.getListing(id));

  Future<void> _accept(
    SwapOfferModel offer,
    ListingModel? mine,
    int othersOnListing,
  ) async {
    setState(() => _busy.add(offer.offerId));
    await acceptSwapOfferFlow(
      context,
      offer: offer,
      mine: mine,
      otherPendingOnListing: othersOnListing,
    );
    if (mounted) setState(() => _busy.remove(offer.offerId));
  }

  Future<void> _decline(SwapOfferModel offer) async {
    setState(() => _busy.add(offer.offerId));
    await declineSwapOffer(context, offer);
    if (mounted) setState(() => _busy.remove(offer.offerId));
  }

  @override
  Widget build(BuildContext context) {
    final seller = context.watch<SellerProvider>();
    final pending = seller.pendingOffers;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        title: Text(
          pending.isEmpty ? 'Swap offers' : 'Swap offers (${pending.length})',
        ),
      ),
      body: seller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : pending.isEmpty
          ? const EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'No pending offers',
              message:
                  'When someone offers a swap for one of your '
                  'items, it shows up here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: pending.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final offer = pending[i];
                final mine = seller.listingById(offer.listingId);
                final others = pending
                    .where(
                      (o) =>
                          o.listingId == offer.listingId &&
                          o.offerId != offer.offerId,
                    )
                    .length;
                return _OfferCard(
                  offer: offer,
                  mine: mine,
                  offered: _offeredItem(offer.offeredItemId),
                  busy: _busy.contains(offer.offerId),
                  onAccept: () => _accept(offer, mine, others),
                  onDecline: () => _decline(offer),
                );
              },
            ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.mine,
    required this.offered,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final SwapOfferModel offer;
  final ListingModel? mine;
  final Future<ListingModel?> offered;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return OutlineCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UserLookup(
            uid: offer.offeredById,
            builder: (context, user) => Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.mist,
                  backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                      ? NetworkImage(user!.photoUrl)
                      : null,
                  child: (user?.photoUrl.isNotEmpty ?? false)
                      ? null
                      : const Icon(
                          Icons.person_outline,
                          size: 18,
                          color: AppColors.gray,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (user?.name.isNotEmpty ?? false)
                            ? user!.name
                            : 'SwidShop user',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      StarRatingDisplay(
                        rating: user?.avgRating ?? 0,
                        reviewCount: user?.completedTransactions,
                        size: 12,
                      ),
                    ],
                  ),
                ),
                Text(
                  offer.createdAt == null
                      ? 'just now'
                      : timeago.format(offer.createdAt!),
                  style: const TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FutureBuilder<ListingModel?>(
                  future: offered,
                  builder: (context, snap) => _ItemSide(
                    caption: 'They offer',
                    listing: snap.data,
                    loading: snap.connectionState == ConnectionState.waiting,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 40, left: 6, right: 6),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.teal,
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: _ItemSide(caption: 'For your', listing: mine),
              ),
            ],
          ),
          if (offer.message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '“${offer.message}”',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemSide extends StatelessWidget {
  const _ItemSide({
    required this.caption,
    required this.listing,
    this.loading = false,
  });

  final String caption;
  final ListingModel? listing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.gray,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) => loading
                ? Container(
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  )
                : ListingThumb(
                    url: (l?.images.isNotEmpty ?? false)
                        ? l!.images.first
                        : null,
                    size: c.maxWidth,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loading ? ' ' : (l?.title ?? 'Item unavailable'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        if (l != null && l.condition.isNotEmpty)
          Text(
            l.condition,
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
          ),
      ],
    );
  }
}
