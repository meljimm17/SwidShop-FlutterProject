import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../providers/listing_provider.dart';
import '../../widgets/top_app_bar.dart';
import 'home_screen.dart' show ListingCard;
import 'live_bidding_screen.dart';

/// Browse open auctions (Phase 3.6, list part).
class BiddingListScreen extends StatelessWidget {
  const BiddingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingProvider>();
    final auctions = provider.auctions;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Live Bidding'),
      body: Column(
        children: [
          _sortChips(context, provider),
          Expanded(
            child: auctions.isEmpty
                ? const Center(
                    child: Text(
                      'No open auctions right now.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: auctions.length,
                    itemBuilder: (context, i) =>
                        _AuctionRow(listing: auctions[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sortChips(BuildContext context, ListingProvider provider) {
    Widget chip(String label, AuctionSort sort) {
      final selected = provider.auctionSort == sort;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => provider.setAuctionSort(sort),
          selectedColor: AppColors.amber,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.amber : AppColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          chip('Ending Soon', AuctionSort.endingSoon),
          chip('Newest', AuctionSort.newest),
          chip('Most Bids', AuctionSort.mostBids),
        ],
      ),
    );
  }
}

class _AuctionRow extends StatelessWidget {
  const _AuctionRow({required this.listing});

  final ListingModel listing;

  @override
  Widget build(BuildContext context) {
    final endingSoon = AppUtils.isEndingSoon(listing.auctionEndAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveBiddingScreen(listingId: listing.listingId),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ListingCard(listing: listing)),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current bid',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                    Text(
                      AppUtils.formatCurrency(
                        listing.currentHighestBid ?? listing.startingBid,
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 15,
                          color: endingSoon
                              ? AppColors.amber
                              : AppColors.gray,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            AppUtils.timeRemaining(listing.auctionEndAt),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: endingSoon
                                  ? AppColors.amber
                                  : AppColors.gray,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${listing.bidCount} bid${listing.bidCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
