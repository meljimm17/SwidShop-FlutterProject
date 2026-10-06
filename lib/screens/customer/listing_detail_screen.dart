import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/bid_model.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/plan_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import '../../widgets/type_badge.dart';
import '../auth/login_screen.dart';
import 'buy_now_screen.dart';
import 'live_bidding_screen.dart';
import 'propose_swap_screen.dart';
import 'search_filter_screen.dart';

/// Full detail view of one listing; exactly one primary CTA per type.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _firestore = FirestoreService();
  int _photoIndex = 0;

  /// Guests (and signed-out users) must log in before any deal action.
  bool _needsLogin() {
    final auth = context.read<AuthProvider>();
    if (auth.isGuest || auth.firebaseUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return true;
    }
    return false;
  }

  Future<void> _toggleFavorite(ListingModel listing) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.firebaseUser?.uid ?? '';
    if (uid.isEmpty || auth.isGuest) {
      _needsLogin();
      return;
    }
    final favs = List<String>.of(auth.profile?.favorites ?? const []);
    if (favs.contains(listing.listingId)) {
      favs.remove(listing.listingId);
    } else {
      favs.add(listing.listingId);
    }
    try {
      await _firestore.updateUserProfile(uid, {'favorites': favs});
    } catch (e) {
      debugPrint('toggleFavorite: $e');
    }
  }

  /// Files a report against the listing and/or its seller (Phase 4.6
  /// queue source). Guests are sent to Login first.
  Future<void> _report(ListingModel listing) async {
    if (_needsLogin()) return;
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty) return;
    final reasonCtrl = TextEditingController();
    var targetSeller = false;
    final send = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setSheet) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is wrong?',
                  hintText: 'e.g. counterfeit, scam, prohibited item…',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Also report the seller',
                  style: TextStyle(fontSize: 14),
                ),
                value: targetSeller,
                onChanged: (v) =>
                    setSheet(() => targetSeller = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
    if (send != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please say what is wrong first.')),
      );
      return;
    }
    try {
      await _firestore.createReport(
        ReportModel(
          reportId: '',
          reportedBy: uid,
          targetType: ReportTargetType.listing,
          targetId: listing.listingId,
          reason: reason,
        ),
      );
      if (targetSeller && listing.sellerId.isNotEmpty) {
        await _firestore.createReport(
          ReportModel(
            reportId: '',
            reportedBy: uid,
            targetType: ReportTargetType.user,
            targetId: listing.sellerId,
            reason: reason,
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks — an admin will review this.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('createReport: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  void _cta(ListingModel listing) {
    if (_needsLogin()) return;
    switch (listing.type) {
      case ListingType.buyNow:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BuyNowScreen(listingId: listing.listingId),
          ),
        );
      case ListingType.bid:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveBiddingScreen(listingId: listing.listingId),
          ),
        );
      case ListingType.swap:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProposeSwapScreen(listingId: listing.listingId),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Listing'),
      body: StreamBuilder<ListingModel?>(
        stream: _firestore.streamListing(widget.listingId),
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
    final sold = listing.status != ListingStatus.active;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 104),
          children: [
            _carousel(listing),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TypeBadge(listing.type),
                      const SizedBox(width: 8),
                      if (sold)
                        StatusPill(
                          listing.status.value,
                          color: AppColors.gray,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          listing.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _FavoriteButton(
                        listingId: listing.listingId,
                        onToggle: () => _toggleFavorite(listing),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _metaRow(listing),
                  const SizedBox(height: 8),
                  _priceBlock(listing),
                  const SizedBox(height: 16),
                  _sellerRow(listing),
                  const SizedBox(height: 16),
                  _specGrid(listing),
                  const SizedBox(height: 12),
                  Text(
                    listing.description.isEmpty
                        ? 'No description provided.'
                        : listing.description,
                    style:
                        const TextStyle(color: AppColors.ink, height: 1.5),
                  ),
                  if (listing.type == ListingType.bid) ...[
                    const SizedBox(height: 20),
                    _bidPreview(listing),
                  ],
                  if (listing.type == ListingType.swap &&
                      listing.swapWants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _swapWants(listing),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _report(listing),
                      icon: const Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: AppColors.gray,
                      ),
                      label: const Text(
                        'Report this listing',
                        style:
                            TextStyle(color: AppColors.gray, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(top: BorderSide(color: AppColors.line)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: sold
                  ? const Center(
                      child: Text(
                        'This item is no longer available.',
                        style: TextStyle(color: AppColors.gray),
                      ),
                    )
                  : _actions(listing),
            ),
          ),
        ),
      ],
    );
  }

  /// Listed-ago · location (mockup meta row, all real data).
  Widget _metaRow(ListingModel listing) {
    return UserLookup(
      uid: listing.sellerId,
      builder: (context, user) {
        final bits = <String>[
          if (listing.createdAt != null)
            'Listed ${timeago.format(listing.createdAt!)}',
          [
            user?.address.city ?? '',
            user?.address.province ?? '',
          ].where((e) => e.isNotEmpty).join(', '),
        ].where((e) => e.isNotEmpty).join(' · ');
        if (bits.isEmpty) return const SizedBox.shrink();
        return Text(
          bits,
          style: const TextStyle(fontSize: 13, color: AppColors.gray),
        );
      },
    );
  }

  Widget _carousel(ListingModel listing) {
    if (listing.images.isEmpty) {
      return Container(
        height: 280,
        color: AppColors.cream,
        child:
            const Icon(Icons.image_outlined, size: 64, color: AppColors.gray),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            itemCount: listing.images.length,
            onPageChanged: (i) => setState(() => _photoIndex = i),
            itemBuilder: (context, i) => CachedNetworkImage(
              imageUrl: listing.images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, _) => Container(color: AppColors.cream),
              errorWidget: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: AppColors.gray,
              ),
            ),
          ),
        ),
        if (listing.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < listing.images.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _photoIndex
                          ? AppColors.coral
                          : AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _priceBlock(ListingModel listing) {
    if (listing.type == ListingType.swap && listing.price == null) {
      return const Text(
        'Open to Swap',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.teal,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppUtils.formatCurrency(listing.displayPrice),
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
      ],
    );
  }

  Widget _sellerRow(ListingModel listing) {
    return UserLookup(
      uid: listing.sellerId,
      builder: (context, user) => Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surface,
            backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                ? NetworkImage(user!.photoUrl)
                : null,
            child: (user?.photoUrl.isNotEmpty ?? false)
                ? null
                : const Icon(Icons.person_outline, color: AppColors.gray),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserNameText(
                  listing.sellerId,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (user != null)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    children: [
                      StarRatingDisplay(
                        rating: user.avgRating,
                        reviewCount: user.completedTransactions,
                        size: 13,
                      ),
                      if (user.trustedBadge) ...[
                        const SizedBox(width: 6),
                        const TrustedBadge(),
                      ],
                      if (user.isVerifiedSeller) ...[
                        const SizedBox(width: 6),
                        PlanBadge(profile: user, compact: true),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchFilterScreen(
                  sellerId: listing.sellerId,
                  sellerName: 'Seller\'s stall',
                ),
              ),
            ),
            child: const Text('Visit Stall'),
          ),
        ],
      ),
    );
  }

  /// Item specifications as a labeled 2×2 grid (mockup spec block).
  Widget _specGrid(ListingModel listing) {
    final specs = <(String, String)>[
      if (listing.condition.isNotEmpty) ('Condition', listing.condition),
      if (listing.size.isNotEmpty) ('Size', listing.size),
      if (listing.fabric.isNotEmpty) ('Fabric', listing.fabric),
      if (listing.brand.isNotEmpty) ('Brand', listing.brand),
    ];
    if (specs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Item Specifications',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
          ),
          itemCount: specs.length,
          itemBuilder: (context, i) => Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  specs[i].$1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gray,
                  ),
                ),
                Text(
                  specs[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bidPreview(ListingModel listing) {
    return StreamBuilder<List<BidModel>>(
      stream: _firestore.streamBids(listing.listingId),
      builder: (context, snap) {
        final bids = snap.data ?? const <BidModel>[];
        if (bids.isEmpty) {
          return const Text(
            'No bids yet — be the first.',
            style: TextStyle(color: AppColors.gray),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${bids.length} bid${bids.length == 1 ? '' : 's'} so far',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final b in bids.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: UserNameText(
                        b.bidderId,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      AppUtils.formatCurrency(b.amount),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _swapWants(ListingModel listing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Seller is looking for: ${listing.swapWants}',
        style: const TextStyle(color: AppColors.ink, height: 1.4),
      ),
    );
  }

  Widget _actions(ListingModel listing) {
    // No self-dealing: owners manage their item from the Seller Centre.
    final mine =
        context.read<AuthProvider>().firebaseUser?.uid == listing.sellerId;
    if (mine) {
      return const Center(
        child: Text(
          'This is your listing.',
          style: TextStyle(color: AppColors.gray),
        ),
      );
    }
    switch (listing.type) {
      case ListingType.buyNow:
        return PrimaryButton(
          label: 'Buy Now — ${AppUtils.formatCurrency(listing.price)}',
          onPressed: () => _cta(listing),
        );
      case ListingType.bid:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              label: 'Place a Bid',
              onPressed: () => _cta(listing),
            ),
            // Pro add-on: instant-buy price, until bids reach it.
            if (listing.buyItNowOpen) ...[
              const SizedBox(height: 10),
              SecondaryButton(
                label:
                    'Buy It Now — ${AppUtils.formatCurrency(listing.buyNowPrice)}',
                icon: Icons.bolt_outlined,
                onPressed: () {
                  if (_needsLogin()) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BuyNowScreen(listingId: listing.listingId),
                    ),
                  );
                },
              ),
            ],
          ],
        );
      case ListingType.swap:
        return SecondaryButton(
          label: 'Offer a Swap',
          icon: Icons.swap_horiz,
          onPressed: () => _cta(listing),
        );
    }
  }
}

/// Heart beside the product title (kept out of the app bar so every
/// TopAppBar keeps one style: plain icons, avatar circle only).
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.listingId, required this.onToggle});

  final String listingId;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isFav = context.select<AuthProvider, bool>(
      (a) => (a.profile?.favorites ?? const []).contains(listingId),
    );
    return IconButton(
      tooltip: isFav ? 'Remove from favorites' : 'Save to favorites',
      icon: Icon(
        isFav ? Icons.favorite : Icons.favorite_border,
        color: isFav ? AppColors.coral : AppColors.gray,
      ),
      onPressed: onToggle,
    );
  }
}
