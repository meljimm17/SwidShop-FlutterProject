import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import '../../widgets/type_badge.dart';

/// Read-only detail view for a single listing.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _firestore = FirestoreService();
  late Future<ListingModel?> _future;

  @override
  void initState() {
    super.initState();
    _future = _firestore.getListing(widget.listingId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Listing'),
      body: FutureBuilder<ListingModel?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final listing = snapshot.data;
          if (listing == null) {
            return const Center(child: Text('Listing not found'));
          }
          return _body(listing);
        },
      ),
    );
  }

  Widget _body(ListingModel listing) {
    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 1.2,
          child: listing.images.isEmpty
              ? Container(
                  color: AppColors.cream,
                  child: const Icon(Icons.image_outlined,
                      size: 64, color: AppColors.gray),
                )
              : PageView(
                  children: listing.images
                      .map((url) => CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AppColors.cream),
                            errorWidget: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.gray,
                            ),
                          ))
                      .toList(),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TypeBadge(listing.type),
                  const SizedBox(width: 8),
                  const TrustedBadge(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                listing.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                AppUtils.formatCurrency(
                  listing.type == ListingType.bid
                      ? listing.currentHighestBid ?? listing.startingBid
                      : listing.price,
                ),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.coral,
                ),
              ),
              if (listing.type == ListingType.bid) ...[
                const SizedBox(height: 4),
                Text(
                  AppUtils.timeRemaining(listing.auctionEndAt),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppUtils.isEndingSoon(listing.auctionEndAt)
                        ? AppColors.amber
                        : AppColors.gray,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                listing.description.isEmpty
                    ? 'No description provided.'
                    : listing.description,
                style: const TextStyle(color: AppColors.ink, height: 1.5),
              ),
              const SizedBox(height: 24),
              _actions(listing),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(ListingModel listing) {
    switch (listing.type) {
      case ListingType.buyNow:
        return PrimaryButton(
          label: 'Buy Now',
          onPressed: () => _todo('Buy Now'),
        );
      case ListingType.bid:
        return PrimaryButton(
          label: 'Place a Bid',
          onPressed: () => _todo('Bidding'),
        );
      case ListingType.swap:
        return SecondaryButton(
          label: 'Offer a Swap',
          icon: Icons.swap_horiz,
          onPressed: () => _todo('Swap'),
        );
    }
  }

  void _todo(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what flow — coming soon')),
    );
  }
}
