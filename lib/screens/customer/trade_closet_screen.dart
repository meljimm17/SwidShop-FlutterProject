import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/top_app_bar.dart';
import 'activity_screen.dart' show ActivityListing;
import 'listing_detail_screen.dart';

/// The seller-side closet: my own listings (Phase 3.11, seller/both only).
class TradeClosetScreen extends StatelessWidget {
  const TradeClosetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'My Trade Closet'),
      body: StreamBuilder<List<ListingModel>>(
        stream: FirestoreService().streamSellerListings(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <ListingModel>[];
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Nothing posted yet.',
                style: TextStyle(color: AppColors.gray),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final l = items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActivityListing(
                  listingId: l.listingId,
                  fallbackTitle: l.title,
                  fallbackImage:
                      l.images.isNotEmpty ? l.images.first : '',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ListingDetailScreen(listingId: l.listingId),
                    ),
                  ),
                  trailing: Text(
                    l.status.value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
