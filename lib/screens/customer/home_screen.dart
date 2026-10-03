import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listing_provider.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../auth/login_screen.dart';
import '../seller/seller_shell.dart';
import 'listing_detail_screen.dart';
import 'profile_screen.dart';

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
    final canSell = !isGuest && (auth.profile?.role.canSell ?? false);
    // A seller-only account reached Home from its Seller Centre.
    final fromSellerCentre = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(
        showLogo: !fromSellerCentre,
        showBack: fromSellerCentre,
        title: fromSellerCentre ? 'Marketplace' : null,
        leadingActions: [
          if (canSell && !fromSellerCentre)
            IconButton(
              tooltip: 'Seller Centre',
              icon: const Icon(Icons.storefront_outlined, color: AppColors.ink),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SellerShell(),
                ),
              ),
            ),
        ],
        onSearch: () => showSearch(
          context: context,
          delegate: _ListingSearchDelegate(context.read<ListingProvider>()),
        ),
        onBell: isGuest
            ? () => _promptLogin(context)
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications coming soon')),
                ),
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
          _typeTabs(listings),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => listings.refresh(),
              child: listings.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : listings.listings.isEmpty
                      ? _emptyState()
                      : _grid(listings.listings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeTabs(ListingProvider listings) {
    Widget chip(String label, ListingType? type, Color color) {
      final selected = listings.type == type;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => listings.setType(type),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.ink,
          ),
          selectedColor: color,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: selected ? color : AppColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          chip('All', null, AppColors.ink),
          chip('Buy Now', ListingType.buyNow, AppColors.coral),
          chip('Bidding', ListingType.bid, AppColors.amber),
          chip('Swap', ListingType.swap, AppColors.teal),
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

  Widget _grid(List<ListingModel> items) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.68,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => ListingCard(listing: items[i]),
      );

  Widget _emptyState() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.storefront_outlined, size: 64, color: AppColors.gray),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No listings yet',
            style: TextStyle(color: AppColors.gray, fontWeight: FontWeight.w500),
          ),
        ),
      ],
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

class _ListingSearchDelegate extends SearchDelegate<String> {
  _ListingSearchDelegate(this.provider);

  final ListingProvider provider;

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) {
    provider.setQuery(query);
    return _grid(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) => _grid(context);

  Widget _grid(BuildContext context) {
    provider.setQuery(query);
    final items = provider.listings;
    if (items.isEmpty) {
      return const Center(child: Text('No matches'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => ListingCard(listing: items[i]),
    );
  }
}
