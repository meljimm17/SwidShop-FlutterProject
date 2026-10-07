import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/system_announcement.dart';
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
import 'sponsored_carousel.dart';
import 'trusted_sellers_screen.dart';

/// Customer home feed of active listings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<SystemAnnouncement> _announcementStream;

  @override
  void initState() {
    super.initState();
    _announcementStream = FirestoreService().streamSystemAnnouncement();
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
    // Home was pushed on top of another screen (show a back button).
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
            SystemAnnouncementBanner(stream: _announcementStream),
            _greeting(auth),
            _quickAccess(context),
            const SponsoredCarousel(),
            const PartnerAdSlot(),
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

  /// Recently Listed + paged grid in one scroll view.
  Widget _feed(BuildContext context, ListingProvider listings) {
    final visible = listings.visibleListings;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: item(Icons.gavel_outlined, 'Bidding', AppColors.amber, () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BiddingListScreen()),
                );
              }),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 62,
              child: item(Icons.swap_horiz, 'Swap', AppColors.teal,
                  () => browseType(ListingType.swap)),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 62,
              child: item(Icons.shopping_bag_outlined, 'Buy Now',
                  AppColors.coral, () => browseType(ListingType.buyNow)),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 62,
              child: item(Icons.grid_view_outlined, 'Categories', AppColors.ink,
                  () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchFilterScreen()),
                );
              }),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 62,
              child: item(Icons.verified_outlined, 'Trusted', AppColors.green,
                  () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrustedSellersScreen(),
                  ),
                );
              }),
            ),
          ],
        ),
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

class SystemAnnouncementBanner extends StatelessWidget {
  const SystemAnnouncementBanner({super.key, required this.stream});

  final Stream<SystemAnnouncement> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SystemAnnouncement>(
      stream: stream,
      builder: (context, snapshot) {
        final announcement = snapshot.data;
        if (announcement == null ||
            !announcement.enabled ||
            announcement.message.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.teal.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_outlined,
                  color: AppColors.teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  announcement.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    final featured = listing.isFeatured;
    final hot = listing.isHighlighted;
    return AppCardWrapper(
      padding: EdgeInsets.zero,
      // Pro Highlight: coral border (+ Hot tag below).
      border: hot ? Border.all(color: AppColors.coral, width: 2) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listing.listingId),
        ),
      ),
      // In a fixed-size grid cell the photo flexes to whatever height is
      // left after the text (no overflow at large system font sizes); in an
      // unbounded list it keeps its 1.1 aspect ratio.
      child: LayoutBuilder(
        builder: (context, c) {
          final bounded = c.hasBoundedHeight;
          final photo = ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.cardRadius),
            ),
            child: image == null
                ? Container(
                    color: AppColors.cream,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_outlined,
                        color: AppColors.gray, size: 40),
                  )
                : CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, _) => Container(color: AppColors.cream),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.gray,
                    ),
                  ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (bounded)
                Expanded(child: photo)
              else
                AspectRatio(aspectRatio: 1.1, child: photo),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      listing.title,
                      maxLines: bounded ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          TypeBadge(listing.type),
                          if (hot) ...[
                            const SizedBox(width: 6),
                            const PromoTag('HOT', color: AppColors.coral),
                          ],
                          if (featured) ...[
                            const SizedBox(width: 6),
                            const PromoTag('FEATURED', color: AppColors.amber),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      listing.type == ListingType.swap && listing.price == null
                          ? 'Swap'
                          : AppUtils.formatCurrency(listing.displayPrice),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          );
        },
      ),
    );
  }
}

/// Small filled pill for feed promos (HOT / FEATURED / SPONSORED).
class PromoTag extends StatelessWidget {
  const PromoTag(this.label, {super.key, this.color = AppColors.coral});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
