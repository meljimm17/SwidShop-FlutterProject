import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../shared/transaction_chat_screen.dart';
import 'auction_time_sheet.dart';
import 'boost_sheet.dart';
import 'monitor_bidding_screen.dart';
import 'plans_screen.dart';
import 'post_listing_screen.dart';
import 'swap_offers_screen.dart';

/// Listings tab: activity hub, filter pills (All / Active / Sold / Done /
/// Expired) with live counts, and listing cards with per-state actions.
/// Edit / Delist lock once a listing has any bid or swap offer.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  /// null = All.
  MyListingTab? _filter;

  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  bool _isPro() =>
      context.read<AuthProvider>().profile?.isPro ?? false;

  /// Paid feature slot (Step 5): anyone can buy; extends an active one.
  Future<void> _feature(BuildContext context, ListingModel l) =>
      featureListing(context, listingId: l.listingId, title: l.title);

  /// Bump allowed once per [AppConstants.bumpCooldown] per listing.
  bool _bumpCoolingDown(ListingModel l) {
    final last = l.bumpedAt;
    return last != null &&
        DateTime.now().difference(last) < AppConstants.bumpCooldown;
  }

  Future<void> _bump(BuildContext context, ListingModel l) async {
    if (!_isPro()) {
      await showUpgradePrompt(context, feature: 'Bump Listing');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreService().bumpListing(l);
      messenger.showSnackBar(
        const SnackBar(content: Text('Bumped to the top of the feed!')),
      );
    } catch (e) {
      debugPrint('bump: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : 'Could not bump. Try again.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  /// Highlight = coral border + Hot tag (Pro perk, no charge).
  Future<void> _highlight(BuildContext context, ListingModel l) async {
    if (!_isPro()) {
      await showUpgradePrompt(context, feature: 'Highlighted Listing');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final until = await FirestoreService().highlightListing(l.listingId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Highlighted until ${AppUtils.formatDate(until)}!'),
        ),
      );
    } catch (e) {
      debugPrint('highlight: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not highlight. Try again.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _delist(ListingModel l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delist this item?'),
        content: Text(
          '"${l.title}" will be hidden from buyers. This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delist'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirestoreService().updateListing(l.listingId, {
        'status': ListingStatus.removed.value,
      });
    } catch (e) {
      debugPrint('delist: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delist. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _manage(ListingModel l, SellerProvider s) async {
    final locked = s.isLocked(l);
    final offers = s.offerCountFor(l.listingId);
    final pro = _isPro();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (l.type == ListingType.bid)
              ListTile(
                leading: const Icon(
                  Icons.insights_outlined,
                  color: AppColors.amber,
                ),
                title: const Text('Monitor bids'),
                subtitle: Text(
                  '${l.bidCount} bid${l.bidCount == 1 ? '' : 's'}',
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _push(MonitorBiddingScreen(listingId: l.listingId));
                },
              ),
            if (offers > 0)
              ListTile(
                leading: const Icon(
                  Icons.sync_alt_rounded,
                  color: AppColors.teal,
                ),
                title: const Text('Review swap offers'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _push(const SwapOffersScreen());
                },
              ),
            ListTile(
              enabled: !locked,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit listing'),
              subtitle: locked
                  ? const Text('Locked — it already has bids or offers')
                  : null,
              onTap: () {
                Navigator.of(sheet).pop();
                _push(PostListingScreen(existing: l));
              },
            ),
            if (l.status == ListingStatus.active &&
                l.type == ListingType.bid &&
                (l.auctionEndAt?.isAfter(DateTime.now()) ?? false))
              ListTile(
                leading: const Icon(
                  Icons.more_time_rounded,
                  color: AppColors.amber,
                ),
                title: const Text('Change end time'),
                subtitle: Text(
                  'Ends ${AppUtils.formatDateTime(l.auctionEndAt)} — make it '
                  'shorter or longer, even with bids',
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  showChangeAuctionEndSheet(context, l);
                },
              ),
            if (l.status == ListingStatus.active) ...[
              ListTile(
                leading: const Icon(
                  Icons.star_outline,
                  color: AppColors.amber,
                ),
                title: const Text('Feature this listing'),
                subtitle: Text(
                  l.isFeatured
                      ? 'Featured until ${AppUtils.formatDate(l.featuredUntil)} — buy more to extend'
                      : '${AppConstants.featuredDays}-day Sponsored slot + Featured tag · ${AppUtils.formatCurrency(AppConstants.featuredPrice)}',
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _feature(context, l);
                },
              ),
              ListTile(
                enabled: !(pro && _bumpCoolingDown(l)),
                leading: const Icon(
                  Icons.arrow_upward_outlined,
                  color: AppColors.teal,
                ),
                title: const Text('Bump listing'),
                subtitle: Text(
                  !pro
                      ? 'Back to the top of the feed, daily (Pro)'
                      : _bumpCoolingDown(l)
                          ? 'Already bumped — available again tomorrow'
                          : 'Back to the top of the feed (once a day)',
                ),
                trailing: pro ? null : const LockIcon(),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _bump(context, l);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.highlight_outlined,
                  color: AppColors.coral,
                ),
                title: const Text('Highlight listing'),
                subtitle: Text(
                  l.isHighlighted
                      ? 'Highlighted until ${AppUtils.formatDate(l.highlightUntil)} (coral border + Hot tag)'
                      : 'Coral border + Hot tag for ${AppConstants.highlightDays} days (Pro)',
                ),
                trailing: pro ? null : const LockIcon(),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _highlight(context, l);
                },
              ),
            ],
            ListTile(
              enabled: !locked,
              leading: Icon(
                Icons.visibility_off_outlined,
                color: locked ? null : AppColors.red,
              ),
              title: Text(
                'Delist',
                style: TextStyle(color: locked ? null : AppColors.red),
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _delist(l);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SellerProvider>();
    final byTab = <MyListingTab, List<ListingModel>>{
      for (final t in MyListingTab.values) t: [],
    };
    for (final l in s.listings) {
      byTab[s.tabFor(l)]!.add(l);
    }
    final txnByListing = s.txnByListing;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        automaticallyImplyLeading: canPop,
        title: const Text(
          'My Listings',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Post new listing',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _push(const PostListingScreen()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: s.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _hub(s),
                const SizedBox(height: 16),
                _filters(s.listings.length, byTab),
                const SizedBox(height: 18),
                ..._sections(s, byTab, txnByListing),
                const SizedBox(height: 12),
                _cta(),
              ],
            ),
    );
  }

  Widget _hub(SellerProvider s) {
    final listed = s.activeListings.fold<double>(
      0,
      (a, l) => a + (l.displayPrice ?? 0),
    );
    final settled = s.completedSales.fold<double>(0, (a, t) => a + t.amount);
    Widget metric(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mist.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.coral.withValues(alpha: 0.14),
                child: const Icon(Icons.hub_outlined, color: AppColors.coral),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Seller Activity Hub',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your inventory, open deals and completed sales, '
                      'updated in real time.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                metric(
                  'Listed value',
                  AppUtils.formatCurrency(listed),
                  AppColors.coralDeep,
                ),
                metric(
                  'Open deals',
                  '${s.openOrders.length}',
                  AppColors.coralDeep,
                ),
                metric(
                  'Settled',
                  AppUtils.formatCurrency(settled),
                  AppColors.coralDeep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(int total, Map<MyListingTab, List<ListingModel>> byTab) {
    Widget pill(String label, int count, MyListingTab? tab) {
      final selected = _filter == tab;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _filter = tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : AppColors.mist,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white70 : AppColors.gray,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          pill('All', total, null),
          pill(
            'Active',
            byTab[MyListingTab.active]!.length,
            MyListingTab.active,
          ),
          pill('Sold', byTab[MyListingTab.sold]!.length, MyListingTab.sold),
          pill('Done', byTab[MyListingTab.done]!.length, MyListingTab.done),
          pill(
            'Expired',
            byTab[MyListingTab.expired]!.length,
            MyListingTab.expired,
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(
    SellerProvider s,
    Map<MyListingTab, List<ListingModel>> byTab,
    Map<String, TransactionModel> txns,
  ) {
    final tabs = _filter == null ? MyListingTab.values : [_filter!];
    final out = <Widget>[];
    for (final tab in tabs) {
      final items = byTab[tab]!;
      if (_filter == null && items.isEmpty) continue;
      out.add(_sectionHeader(tab, items));
      out.add(const SizedBox(height: 10));
      if (items.isEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing here yet',
              message: switch (tab) {
                MyListingTab.active => 'Post an item and it shows up here.',
                MyListingTab.sold =>
                  'Items with a winner or accepted swap wait here until '
                      'the deal is completed.',
                MyListingTab.done => 'Completed deals are archived here.',
                MyListingTab.expired =>
                  'Auctions that ended unsold and delisted items show here.',
              },
            ),
          ),
        );
      }
      for (final l in items) {
        out.add(
          _ListingCard(
            listing: l,
            txn: txns[l.listingId],
            pendingOffers: s.pendingOffers
                .where((o) => o.listingId == l.listingId)
                .length,
            onManage: () => _manage(l, s),
            onReviewOffers: () => _push(const SwapOffersScreen()),
            onOpenChat: (id) => _push(TransactionChatScreen(transactionId: id)),
          ),
        );
        out.add(const SizedBox(height: 12));
      }
      out.add(const SizedBox(height: 8));
    }
    if (out.isEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: EmptyState(
            icon: Icons.checkroom_rounded,
            title: 'No listings yet',
            message: 'Your first ukay find is one tap away.',
          ),
        ),
      );
    }
    return out;
  }

  Widget _sectionHeader(MyListingTab tab, List<ListingModel> items) {
    final endingSoon = tab == MyListingTab.active
        ? items
              .where(
                (l) =>
                    l.type == ListingType.bid &&
                    AppUtils.isEndingSoon(l.auctionEndAt),
              )
              .length
        : 0;
    final (String title, Color dot, String? chip) = switch (tab) {
      MyListingTab.active => (
        'Active Listings',
        AppColors.coral,
        endingSoon > 0 ? '$endingSoon ending soon' : null,
      ),
      MyListingTab.sold => (
        'Sold Listings',
        AppColors.green,
        items.isEmpty ? null : 'Arrange handover',
      ),
      MyListingTab.done => ('Done / Completed', AppColors.teal, null),
      MyListingTab.expired => ('Expired & Delisted', AppColors.gray, null),
    };
    return Row(
      children: [
        tab == MyListingTab.done
            ? const Icon(
                Icons.check_circle_outline,
                size: 18,
                color: AppColors.teal,
              )
            : Icon(Icons.circle, size: 10, color: dot),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        if (chip != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chip,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cta() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.mist.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.add_box_outlined, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ready to clear your rack?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sell at a fixed price, run an auction, or swap with the '
            'community.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF55534E)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _push(const PostListingScreen()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coralDeep,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'List New Ukay Item',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.txn,
    required this.pendingOffers,
    required this.onManage,
    required this.onReviewOffers,
    required this.onOpenChat,
  });

  final ListingModel listing;
  final TransactionModel? txn;
  final int pendingOffers;
  final VoidCallback onManage;
  final VoidCallback onReviewOffers;
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final active = l.status == ListingStatus.active;
    final sold = l.status == ListingStatus.sold;
    final isBid = l.type == ListingType.bid;

    final meta = [
      if (l.category.isNotEmpty) l.category.toUpperCase(),
      if (l.size.isNotEmpty) 'SIZE ${l.size.toUpperCase()}',
    ].join(' • ');

    final String? imageTag = switch (l.status) {
      ListingStatus.sold => 'SOLD',
      ListingStatus.expired => 'ENDED',
      ListingStatus.removed => 'DELISTED',
      ListingStatus.active =>
        l.type == ListingType.swap && l.swapOnly ? 'Swap Only' : null,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ListingThumb(
                url: l.images.isNotEmpty ? l.images.first : null,
                size: 104,
                radius: 16,
              ),
              if (active && isBid && AppUtils.isEndingSoon(l.auctionEndAt))
                const Positioned(
                  left: 6,
                  top: 6,
                  child: _ImageTag('ENDING SOON', dark: true),
                ),
              if (imageTag != null)
                Positioned(left: 6, bottom: 6, child: _ImageTag(imageTag)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta.isEmpty ? _typeLabel(l.type).toUpperCase() : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.gray,
                        ),
                      ),
                    ),
                    if (active && isBid && l.auctionEndAt != null)
                      _MiniChip(
                        icon: Icons.timer_outlined,
                        text: AppUtils.timeRemaining(l.auctionEndAt),
                        bg: AppColors.amber.withValues(alpha: 0.18),
                        fg: const Color(0xFF8A5A0B),
                      )
                    else if (active && pendingOffers > 0)
                      _MiniChip(
                        icon: Icons.sync_alt_rounded,
                        text: 'Swap pending',
                        bg: AppColors.teal.withValues(alpha: 0.14),
                        fg: AppColors.teal,
                      )
                    else if (txn != null)
                      StatusPill.transaction(txn!.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                _priceLine(l, sold),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _footInfo(l, active)),
                    _action(l, active),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(ListingType t) => switch (t) {
    ListingType.buyNow => 'Buy Now',
    ListingType.bid => 'Auction',
    ListingType.swap => 'Swap',
  };

  Widget _priceLine(ListingModel l, bool sold) {
    const big = TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w800,
      color: AppColors.coralDeep,
    );
    const small = TextStyle(fontSize: 13, color: AppColors.gray);

    if ((sold || l.status == ListingStatus.sold) && txn != null) {
      return Row(
        children: [
          Text(
            txn!.type == ListingType.swap
                ? 'Swapped'
                : AppUtils.formatCurrency(txn!.amount),
            style: big,
          ),
          const Text('  to ', style: small),
          Flexible(
            child: UserNameText(
              txn!.buyerId,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.teal,
              ),
            ),
          ),
        ],
      );
    }
    switch (l.type) {
      case ListingType.bid:
        return Text.rich(
          TextSpan(
            text: l.hasBids ? 'Top bid: ' : 'Starts at: ',
            style: small,
            children: [
              TextSpan(
                text: AppUtils.formatCurrency(l.displayPrice),
                style: big,
              ),
              if (l.hasBids && l.startingBid != null)
                TextSpan(
                  text: '  ${AppUtils.formatCurrency(l.startingBid)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.gray,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case ListingType.buyNow:
        return Text(AppUtils.formatCurrency(l.price), style: big);
      case ListingType.swap:
        return Text.rich(
          TextSpan(
            text: 'Looking for: ',
            style: small,
            children: [
              TextSpan(
                text: l.swapWants.isEmpty ? 'Open to offers' : l.swapWants,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _footInfo(ListingModel l, bool active) {
    const style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
    if (active && l.type == ListingType.bid) {
      return Row(
        children: [
          const Icon(Icons.circle, size: 7, color: AppColors.amber),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l.bidCount == 0
                  ? 'No bids yet'
                  : '${l.bidCount} competitive bid${l.bidCount == 1 ? '' : 's'}',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }
    if (active && l.type == ListingType.swap) {
      return Row(
        children: [
          const Icon(Icons.sync_alt_rounded, size: 15, color: AppColors.teal),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$pendingOffers open offer${pendingOffers == 1 ? '' : 's'}',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }
    if (txn?.status == TransactionStatus.completed) {
      return Text(
        'Completed ${AppUtils.formatDate(txn!.createdAt)}',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
      );
    }
    if (l.status == ListingStatus.expired ||
        l.status == ListingStatus.removed) {
      return Text(
        l.status == ListingStatus.removed
            ? 'Hidden from buyers'
            : 'Ended unsold',
        style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _action(ListingModel l, bool active) {
    Widget pill(
      String label,
      Color bg,
      VoidCallback onTap, {
      IconData? icon,
    }) => FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 16)],
        ],
      ),
    );

    if (active && pendingOffers > 0) {
      return pill('Review ($pendingOffers)', AppColors.teal, onReviewOffers);
    }
    if (active) {
      return pill(
        'Manage',
        AppColors.coralDeep,
        onManage,
        icon: Icons.arrow_forward_rounded,
      );
    }
    if (txn != null) {
      return OutlinedButton(
        onPressed: () => onOpenChat(txn!.transactionId),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: const Text('Open chat'),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ImageTag extends StatelessWidget {
  const _ImageTag(this.text, {this.dark = false});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.ink.withValues(alpha: 0.8)
            : AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: dark ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
