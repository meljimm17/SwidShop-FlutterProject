import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/swap_offer_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import 'analytics_screen.dart';
import 'monitor_bidding_screen.dart';
import 'post_listing_screen.dart';
import 'sales_history_screen.dart';
import 'seller_orders_screen.dart';
import 'seller_shell.dart';
import 'swap_offer_actions.dart';
import 'swap_offers_screen.dart';

/// Seller Dashboard (Dashboard tab of [SellerShell]): store card with
/// Post New Listing, live Store Pulse stats, management tools and a live
/// feed of auctions with bids, pending swap offers and open orders.
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final Map<String, Future<ListingModel?>> _offeredItems = {};
  final Set<String> _busyOffers = {};

  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<ListingModel?> _offeredItem(String id) =>
      _offeredItems.putIfAbsent(id, () => FirestoreService().getListing(id));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final seller = context.watch<SellerProvider>();
    final profile = auth.profile;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        automaticallyImplyLeading: canPop,
        titleSpacing: canPop ? 0 : 20,
        title: const Text(
          'Seller Dashboard',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifications coming soon')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: GestureDetector(
              onTap: () => SellerShell.goTo(context, SellerTab.profile),
              child: _avatar(profile, radius: 18, onCoral: true),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _storeCard(profile),
          const SizedBox(height: 24),
          _sectionHeader(
            'STORE PULSE',
            trailing: seller.isLoading ? 'Loading…' : 'Updated just now',
          ),
          const SizedBox(height: 10),
          ..._pulse(seller),
          if (seller.error != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Some numbers could not load. Reopen Seller Centre to retry.',
                style: TextStyle(fontSize: 12.5, color: AppColors.red),
              ),
            ),
          const SizedBox(height: 24),
          _sectionHeader('MANAGEMENT TOOLS'),
          const SizedBox(height: 10),
          _tools(seller),
          const SizedBox(height: 28),
          _feed(seller),
          const SizedBox(height: 20),
          const _TipCard(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Store card
  // ---------------------------------------------------------------------------

  Widget _avatar(UserModel? p, {double radius = 28, bool onCoral = false}) {
    final hasPhoto = p != null && p.photoUrl.isNotEmpty;
    final initials = (p?.name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: onCoral
          ? AppColors.coralDeep
          : AppColors.teal.withValues(alpha: 0.15),
      backgroundImage: hasPhoto ? NetworkImage(p.photoUrl) : null,
      child: hasPhoto
          ? null
          : initials.isEmpty
          ? Icon(
              Icons.person_outline,
              size: radius,
              color: onCoral ? Colors.white : AppColors.teal,
            )
          : Text(
              initials,
              style: TextStyle(
                fontSize: radius * 0.62,
                fontWeight: FontWeight.w800,
                color: onCoral ? Colors.white : AppColors.teal,
              ),
            ),
    );
  }

  Widget _storeCard(UserModel? p) {
    final trusted = p?.trustedBadge ?? false;
    final city = p?.address.city ?? '';
    final ratings = p?.completedTransactions ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mist.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _avatar(p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            (p?.name.isNotEmpty ?? false)
                                ? p!.name
                                : 'My store',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (trusted) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_outlined,
                            size: 18,
                            color: AppColors.green,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: AppColors.amber,
                            ),
                          ),
                          TextSpan(
                            text: ' ${(p?.avgRating ?? 0).toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' ($ratings rating${ratings == 1 ? '' : 's'})'
                                '${city.isEmpty ? '' : ' • $city'}',
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              if (trusted) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 7, color: AppColors.green),
                      SizedBox(width: 5),
                      Text(
                        'PRO SELLER',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: () => _push(const PostListingScreen()),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coralDeep,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: AppColors.coralDeep.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text(
                'Post New Listing',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.ink,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.coralDeep,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Store pulse
  // ---------------------------------------------------------------------------

  List<Widget> _pulse(SellerProvider s) {
    final loading = s.isLoading;
    final added = s.listingsAddedThisWeek;
    final pending = s.pendingOffers.length;
    final change = s.salesChangePercent;
    final deals = s.dealsThisMonth;
    return [
      _PulseCard(
        icon: Icons.inventory_2_outlined,
        iconBg: AppColors.mist,
        iconColor: AppColors.ink,
        label: 'Active Listings',
        value: loading ? null : '${s.activeListings.length}',
        chip: !loading && added > 0
            ? _Chip(
                icon: Icons.trending_up_rounded,
                text: '+$added this week',
                bg: AppColors.mist,
                fg: AppColors.ink,
              )
            : null,
        onTap: () => SellerShell.goTo(context, SellerTab.listings),
      ),
      const SizedBox(height: 10),
      _PulseCard(
        icon: Icons.sync_alt_rounded,
        iconBg: AppColors.teal.withValues(alpha: 0.12),
        iconColor: AppColors.teal,
        label: 'Pending Swap Offers',
        value: loading ? null : '$pending',
        valueColor: AppColors.teal,
        chip: !loading && pending > 0
            ? _Chip(
                icon: Icons.priority_high_rounded,
                text: 'NEEDS REVIEW',
                bg: AppColors.teal.withValues(alpha: 0.15),
                fg: AppColors.teal,
              )
            : null,
        onTap: () => _push(const SwapOffersScreen()),
      ),
      const SizedBox(height: 10),
      _PulseCard(
        icon: Icons.payments_outlined,
        iconBg: AppColors.amber.withValues(alpha: 0.14),
        iconColor: AppColors.amber,
        label: 'Sales This Month',
        value: loading ? null : AppUtils.formatCurrency(s.salesThisMonth),
        valueSuffix: loading ? null : ' / $deals deal${deals == 1 ? '' : 's'}',
        chip: !loading && change != null
            ? _Chip(
                icon: change >= 0
                    ? Icons.north_east_rounded
                    : Icons.south_east_rounded,
                text: '${change >= 0 ? '+' : ''}$change%',
                bg: AppColors.mist,
                fg: change >= 0 ? AppColors.green : AppColors.red,
              )
            : null,
        onTap: () => _push(const SalesHistoryScreen()),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Management tools
  // ---------------------------------------------------------------------------

  Widget _tools(SellerProvider s) {
    final pending = s.pendingOffers.length;
    final sellThrough = SellerStats.sellThrough(s.listings);
    final tiles = <Widget>[
        _ToolTile(
          icon: Icons.checkroom_rounded,
          iconBg: AppColors.mist,
          iconColor: AppColors.ink,
          title: 'My Listings',
          caption: 'Manage inventory',
          badge: s.listings.isEmpty
              ? null
              : _Chip(
                  text: '${s.listings.length}',
                  bg: AppColors.coralDeep,
                  fg: Colors.white,
                ),
          onTap: () => SellerShell.goTo(context, SellerTab.listings),
        ),
        _ToolTile(
          icon: Icons.sync_alt_rounded,
          iconBg: AppColors.teal.withValues(alpha: 0.12),
          iconColor: AppColors.teal,
          title: 'Swap Offers',
          caption: 'Review trades',
          badge: pending == 0
              ? null
              : _Chip(
                  text: '$pending New',
                  bg: AppColors.teal,
                  fg: Colors.white,
                ),
          onTap: () => _push(const SwapOffersScreen()),
        ),
        _ToolTile(
          icon: Icons.receipt_long_outlined,
          iconBg: AppColors.mist,
          iconColor: AppColors.ink,
          title: 'Sales History',
          caption: 'Completed deals',
          badge: const Icon(Icons.chevron_right, color: AppColors.gray),
          onTap: () => _push(const SalesHistoryScreen()),
        ),
        _ToolTile(
          icon: Icons.bar_chart_rounded,
          iconBg: AppColors.amber.withValues(alpha: 0.14),
          iconColor: AppColors.amber,
          title: 'Analytics',
          caption: 'Sell-through & sales',
          badge: sellThrough == null
              ? null
              : Text(
                  '${(sellThrough * 100).round()}% sold',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
          onTap: () => _push(const AnalyticsScreen()),
        ),
    ];
    Widget row(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ],
          ),
        );
    return Column(
      children: [
        row(tiles[0], tiles[1]),
        const SizedBox(height: 10),
        row(tiles[2], tiles[3]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live seller feed
  // ---------------------------------------------------------------------------

  Widget _feed(SellerProvider s) {
    final auctions = s.biddedAuctions.take(2).toList();
    final offers = s.pendingOffers.take(2).toList();
    final orders = s.openOrders.take(2).toList();
    final empty = auctions.isEmpty && offers.isEmpty && orders.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Flexible(
              child: Text(
                'Live Seller Feed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.circle, size: 9, color: AppColors.red),
            const Spacer(),
            TextButton(
              onPressed: () => SellerShell.goTo(context, SellerTab.listings),
              style: TextButton.styleFrom(foregroundColor: AppColors.coralDeep),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (s.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (empty)
          const OutlineCard(
            child: Row(
              children: [
                Icon(Icons.bolt_outlined, color: AppColors.gray),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'New bids, swap offers and orders will appear here as '
                    'they happen.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: AppColors.gray,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          for (final l in auctions) ...[
            _AuctionFeedCard(
              listing: l,
              onReview: () =>
                  _push(MonitorBiddingScreen(listingId: l.listingId)),
            ),
            const SizedBox(height: 12),
          ],
          for (final o in offers) ...[
            _OfferFeedCard(
              offer: o,
              mine: s.listingById(o.listingId),
              offered: _offeredItem(o.offeredItemId),
              busy: _busyOffers.contains(o.offerId),
              onDecline: () async {
                setState(() => _busyOffers.add(o.offerId));
                await declineSwapOffer(context, o);
                if (mounted) setState(() => _busyOffers.remove(o.offerId));
              },
              onAccept: () async {
                setState(() => _busyOffers.add(o.offerId));
                await acceptSwapOfferFlow(
                  context,
                  offer: o,
                  mine: s.listingById(o.listingId),
                  otherPendingOnListing: s.pendingOffers
                      .where(
                        (x) =>
                            x.listingId == o.listingId &&
                            x.offerId != o.offerId,
                      )
                      .length,
                );
                if (mounted) setState(() => _busyOffers.remove(o.offerId));
              },
            ),
            const SizedBox(height: 12),
          ],
          for (final t in orders) ...[
            OrderCard(txn: t),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.bg,
    required this.fg,
    this.icon,
  });

  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    this.valueSuffix,
    this.valueColor = AppColors.ink,
    this.chip,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? value;
  final String? valueSuffix;
  final Color valueColor;
  final Widget? chip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: iconBg,
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF55534E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    value == null
                        ? Container(
                            width: 56,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.mist,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                text: value,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: valueColor,
                                  letterSpacing: -0.4,
                                ),
                                children: [
                                  if (valueSuffix != null)
                                    TextSpan(
                                      text: valueSuffix,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.gray,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              ?chip,
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.caption,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String caption;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: iconBg,
                    child: Icon(icon, size: 21, color: iconColor),
                  ),
                  const Spacer(),
                  ?badge,
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedShell extends StatelessWidget {
  const _FeedShell({required this.top, required this.footer});

  final Widget top;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          top,
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: footer,
          ),
        ],
      ),
    );
  }
}

class _AuctionFeedCard extends StatelessWidget {
  const _AuctionFeedCard({required this.listing, required this.onReview});

  final ListingModel listing;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final left = AppUtils.timeRemaining(l.auctionEndAt).replaceAll(' left', '');
    return _FeedShell(
      top: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListingThumb(
            url: l.images.isNotEmpty ? l.images.first : null,
            size: 76,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: _Chip(
                        icon: Icons.timer_outlined,
                        text: 'Bid ends in $left',
                        bg: AppColors.amber.withValues(alpha: 0.18),
                        fg: const Color(0xFF8A5A0B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${l.bidCount} bid${l.bidCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: 'Current bid: ',
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: AppUtils.formatCurrency(l.currentHighestBid),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.coralDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          const Text(
            'Leading: ',
            style: TextStyle(fontSize: 13, color: AppColors.gray),
          ),
          Expanded(
            child: UserNameText(
              l.highestBidderId,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          _PillButton(label: 'Review Bids', onTap: onReview),
        ],
      ),
    );
  }
}

class _OfferFeedCard extends StatelessWidget {
  const _OfferFeedCard({
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
    return _FeedShell(
      top: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ListingThumb(
                url: (mine?.images.isNotEmpty ?? false)
                    ? mine!.images.first
                    : null,
                size: 76,
              ),
              const Positioned(
                right: -4,
                bottom: -4,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.teal,
                  child: Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Chip(
                      icon: Icons.sync_alt_rounded,
                      text: 'Swap Offer',
                      bg: AppColors.teal.withValues(alpha: 0.14),
                      fg: AppColors.teal,
                    ),
                    const Spacer(),
                    Text(
                      offer.createdAt == null
                          ? 'just now'
                          : timeago.format(offer.createdAt!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mine?.title ?? 'Your item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FutureBuilder<ListingModel?>(
                  future: offered,
                  builder: (context, snap) => Text.rich(
                    TextSpan(
                      text: 'Offered: ',
                      children: [
                        TextSpan(
                          text: snap.data?.title ?? '…',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.gray),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          const Text(
            'From: ',
            style: TextStyle(fontSize: 13, color: AppColors.gray),
          ),
          Expanded(
            child: UserNameText(
              offer.offeredById,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onDecline,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Decline',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: busy ? null : onAccept,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Accept'),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            AppColors.coral.withValues(alpha: 0.10),
            AppColors.teal.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.lightbulb_outline, color: AppColors.coralDeep),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Show the tags',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'Close-ups of the brand, size and care labels help buyers '
                  'trust your listing and decide faster.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
