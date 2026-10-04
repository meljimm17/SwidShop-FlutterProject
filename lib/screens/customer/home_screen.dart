import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listing_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../auth/login_screen.dart';
import '../seller/seller_shell.dart';
import 'bidding_list_screen.dart';
import 'listing_detail_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_filter_screen.dart';
import 'trusted_sellers_screen.dart';

/// Customer home feed of active listings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ListingProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final listings = context.watch<ListingProvider>();
    final isGuest = auth.isGuest;
    final uid = auth.firebaseUser?.uid ?? '';
    final canSell = !isGuest && (auth.profile?.role.canSell ?? false);
    // A seller-only account reached Home from its Seller Centre.
    final fromSellerCentre = Navigator.of(context).canPop();

    Widget scaffold(int unread) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: TopAppBar(
          showLogo: !fromSellerCentre,
          showBack: fromSellerCentre,
          title: fromSellerCentre ? 'Marketplace' : null,
                  extraActions: [
            if (canSell && !fromSellerCentre)
              IconButton(
                tooltip: 'Seller Centre',
                icon:
                    const Icon(Icons.storefront_outlined, color: AppColors.ink),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SellerShell(),
                  ),
                ),
              ),
          ],
          onSearch: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchFilterScreen()),
          ),
          onBell: isGuest
              ? () => _promptLogin(context)
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
          notificationCount: unread,
          onAvatar: () {
            if (isGuest) {
              _promptLogin(context);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }
          },
          avatarUrl: auth.profile?.photoUrl,
        ),
        body: Column(
          children: [
            if (isGuest) _guestBanner(context),
            _greeting(auth),
            _searchBar(context),
            _quickAccess(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => listings.refresh(),
                child: listings.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _feed(context, listings),
              ),
            ),
          ],
        ),
      );
    }

    if (isGuest || uid.isEmpty) return scaffold(0);
    return StreamBuilder<List<NotificationModel>>(
      stream: FirestoreService().streamNotifications(uid),
      builder: (context, snap) {
        final unread =
            (snap.data ?? const <NotificationModel>[])
                .where((n) => !n.read)
                .length;
        return scaffold(unread);
      },
    );
  }

  /// Recently Listed + Trusted row + paged grid in one scroll view.
  Widget _feed(BuildContext context, ListingProvider listings) {
    final visible = listings.visibleListings;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _trustedRow(context, listings),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            listings.hasActiveFilters ? 'Results' : 'Recently Listed',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (visible.isEmpty)
          _emptyState()
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.68,
            ),
            itemCount: listings.hasMore ? visible.length + 1 : visible.length,
            itemBuilder: (context, i) {
              if (i >= visible.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  context.read<ListingProvider>().showMore();
                });
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return ListingCard(listing: visible[i]);
            },
          ),
      ],
    );
  }

  /// Horizontal Trusted-sellers strip; hidden while filtering or empty.
  Widget _trustedRow(BuildContext context, ListingProvider listings) {
    if (listings.hasActiveFilters || listings.query.trim().isNotEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<UserModel>>(
      stream: FirestoreService().streamTrustedUsers(),
      builder: (context, snap) {
        final sellers = (snap.data ?? const <UserModel>[])
            .where((u) =>
                u.role == UserRole.seller || u.role == UserRole.both)
            .take(10)
            .toList();
        if (sellers.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trusted Sellers',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TrustedSellersScreen(),
                      ),
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sellers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final s = sellers[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchFilterScreen(
                          sellerId: s.uid,
                          sellerName: s.name.isEmpty
                              ? 'Stall'
                              : '${s.name}\'s stall',
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.surface,
                          backgroundImage: s.photoUrl.isNotEmpty
                              ? NetworkImage(s.photoUrl)
                              : null,
                          child: s.photoUrl.isEmpty
                              ? const Icon(Icons.storefront_outlined,
                                  color: AppColors.gray)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            s.name.isEmpty ? 'Seller' : s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Greeting header (mockup "Mabuhay" block — real display name only).
  Widget _greeting(AuthProvider auth) {
    final name = auth.profile?.name.trim() ?? '';
    final first = name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first == null ? 'Mabuhay!' : 'Mabuhay, $first!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'Explore today\u2019s drops',
              style: TextStyle(color: AppColors.gray, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SearchFilterScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            border: Border.all(color: AppColors.line),
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: AppColors.gray, size: 20),
              SizedBox(width: 10),
              Text(
                'Search thrift finds',
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAccess(BuildContext context) {
    Widget item(IconData icon, String label, Color color, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    void browseType(ListingType type) {
      // Navigation only — Home always shows the full feed; Search owns
      // the type filter (passed as its initial state).
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SearchFilterScreen(initialType: type),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          item(Icons.gavel_outlined, 'Bidding', AppColors.amber, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BiddingListScreen()),
            );
          }),
          item(Icons.swap_horiz, 'Swap', AppColors.teal,
              () => browseType(ListingType.swap)),
          item(Icons.shopping_bag_outlined, 'Buy Now', AppColors.coral,
              () => browseType(ListingType.buyNow)),
          item(Icons.grid_view_outlined, 'Categories', AppColors.ink, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchFilterScreen()),
            );
          }),
          item(Icons.verified_outlined, 'Trusted', AppColors.green, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TrustedSellersScreen(),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Guests browse read-only; any account action routes to Login.
  void _promptLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Widget _guestBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.teal.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Browsing as guest — log in to bid, buy, or swap.',
              style: TextStyle(fontSize: 12, color: AppColors.ink),
            ),
          ),
          TextButton(
            onPressed: () => _promptLogin(context),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, size: 64, color: AppColors.gray),
          SizedBox(height: 12),
          Center(
            child: Text(
              'No listings yet',
              style:
                  TextStyle(color: AppColors.gray, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable listing tile used by the home feed and search results.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing});

  final ListingModel listing;

  @override
  Widget build(BuildContext context) {
    final image = listing.images.isNotEmpty ? listing.images.first : null;
    return AppCardWrapper(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listing.listingId),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.cardRadius),
            ),
            child: AspectRatio(
              aspectRatio: 1.1,
              child: image == null
                  ? Container(
                      color: AppColors.cream,
                      child: const Icon(Icons.image_outlined,
                          color: AppColors.gray, size: 40),
                    )
                  : CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.cream),
                      errorWidget: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.gray,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                TypeBadge(listing.type),
                const SizedBox(height: 6),
                Text(
                  listing.type == ListingType.swap && listing.price == null
                      ? 'Swap'
                      : AppUtils.formatCurrency(listing.displayPrice),
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
