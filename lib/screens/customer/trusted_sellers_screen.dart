import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import 'search_filter_screen.dart';

/// Directory of Trusted-badge sellers (Phase 3.3).
class TrustedSellersScreen extends StatefulWidget {
  const TrustedSellersScreen({super.key});

  @override
  State<TrustedSellersScreen> createState() => _TrustedSellersScreenState();
}

class _TrustedSellersScreenState extends State<TrustedSellersScreen> {
  final _firestore = FirestoreService();

  Future<void> _toggleFollow(String uid, List<String> following) async {
    final me = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (me.isEmpty) return;
    final next = following.contains(uid)
        ? (List<String>.of(following)..remove(uid))
        : (List<String>.of(following)..add(uid));
    try {
      await _firestore.updateUserProfile(me, {'following': next});
    } catch (e) {
      debugPrint('toggleFollow: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Trusted Sellers'),
      body: StreamBuilder<List<UserModel>>(
        stream: _firestore.streamTrustedUsers(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Badge + seller role only; sort already applied service-side.
          final sellers = (snap.data ?? const <UserModel>[])
              .where((u) => u.role == UserRole.seller || u.role == UserRole.both)
              .toList();
          if (sellers.isEmpty) {
            return const Center(
              child: Text(
                'No Trusted sellers yet.',
                style: TextStyle(color: AppColors.gray),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sellers.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SellerCard(
                seller: sellers[i],
                onFollow: _toggleFollow,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.seller, required this.onFollow});

  final UserModel seller;
  final Future<void> Function(String uid, List<String> following) onFollow;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().profile;
    final followed = me?.following.contains(seller.uid) ?? false;

    return AppCardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.cream,
                backgroundImage: seller.photoUrl.isNotEmpty
                    ? NetworkImage(seller.photoUrl)
                    : null,
                child: seller.photoUrl.isEmpty
                    ? const Icon(Icons.storefront_outlined,
                        color: AppColors.gray)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            seller.name.isEmpty ? 'Seller' : seller.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const TrustedBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    StarRatingDisplay(
                      rating: seller.avgRating,
                      reviewCount: seller.completedTransactions,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PreviewRow(sellerId: seller.uid),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: me == null
                      ? null
                      : () => onFollow(
                            seller.uid,
                            List<String>.of(me.following),
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        followed ? AppColors.gray : AppColors.teal,
                    side: BorderSide(
                      color: followed ? AppColors.line : AppColors.teal,
                    ),
                  ),
                  child: Text(followed ? 'Following' : 'Follow'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchFilterScreen(
                        sellerId: seller.uid,
                        sellerName: seller.name.isEmpty
                            ? 'Stall'
                            : '${seller.name}\'s stall',
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                  ),
                  child: const Text('Visit Stall'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Up to 3 most recent active listings of one seller (client-side take).
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ListingModel>>(
      stream: FirestoreService().streamSellerListings(sellerId),
      builder: (context, snap) {
        final items = (snap.data ?? const <ListingModel>[])
            .where((l) => l.status == ListingStatus.active)
            .take(3)
            .toList();
        if (items.isEmpty) {
          return const Text(
            'No active listings right now.',
            style: TextStyle(color: AppColors.gray, fontSize: 12),
          );
        }
        return SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final l = items[i];
              return SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.expand(
                          child: ListingThumb(
                            url: l.images.isNotEmpty ? l.images.first : '',
                            size: 104,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
