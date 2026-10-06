import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/partner_ad_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../customer/listing_detail_screen.dart';

/// Auto-sliding "Sponsored" carousel (Steps 4–5): active listings of
/// boosted sellers + featured listings. Hidden when empty.
class SponsoredCarousel extends StatefulWidget {
  const SponsoredCarousel({super.key});

  @override
  State<SponsoredCarousel> createState() => _SponsoredCarouselState();
}

class _SponsoredCarouselState extends State<SponsoredCarousel> {
  final _firestore = FirestoreService();
  // Created once: rebuilding (every slide) must not re-subscribe.
  late final Stream<List<ListingModel>> _listings =
      _firestore.streamActiveListings();
  late final Stream<List<UserModel>> _boosted =
      _firestore.streamBoostedSellers();
  final _page = PageController(viewportFraction: 0.85);
  Timer? _timer;
  int _index = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _restart(int count) {
    _timer?.cancel();
    _count = count;
    if (_index >= count) _index = 0;
    if (count < 2) return;
    _timer = Timer.periodic(AppConstants.sponsoredSlideInterval, (_) {
      if (!_page.hasClients) return;
      _index = (_index + 1) % count;
      _page.animateToPage(
        _index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ListingModel>>(
      stream: _listings,
      builder: (context, listingSnap) {
        return StreamBuilder<List<UserModel>>(
          stream: _boosted,
          builder: (context, boostSnap) {
            final items = listingSnap.data ?? const <ListingModel>[];
            final boostedIds = (boostSnap.data ?? const <UserModel>[])
                .map((u) => u.uid)
                .toSet();
            final cards = items
                .where((l) =>
                    l.isFeatured || boostedIds.contains(l.sellerId))
                .toList();
            if (cards.isEmpty) return const SizedBox.shrink();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _count != cards.length) {
                setState(() => _restart(cards.length));
              }
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'Sponsored',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  height: 190,
                  child: PageView.builder(
                    controller: _page,
                    itemCount: cards.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) =>
                        _card(context, cards[i]),
                  ),
                ),
                if (cards.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < cards.length; i++)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 3,
                            ),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _index
                                  ? AppColors.coral
                                  : AppColors.line,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _card(BuildContext context, ListingModel listing) {
    final image =
        listing.images.isNotEmpty ? listing.images.first : null;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listing.listingId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 8, 6, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 140,
              height: double.infinity,
              child: image == null
                  ? Container(
                      color: AppColors.cream,
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.gray,
                      ),
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PromoTag(
                      label: listing.isFeatured ? 'Featured' : 'Sponsored',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppUtils.formatCurrency(listing.displayPrice),
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
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

/// Slim rotating partner-ad slot for the Home feed (Step 6, display only).
class PartnerAdSlot extends StatefulWidget {
  const PartnerAdSlot({super.key});

  @override
  State<PartnerAdSlot> createState() => _PartnerAdSlotState();
}

class _PartnerAdSlotState extends State<PartnerAdSlot> {
  late final Stream<List<PartnerAdModel>> _stream =
      FirestoreService().streamAllPartnerAds();
  Timer? _timer;
  int _index = 0;

  /// Latest live ads (the timer reads this, never a stale snapshot).
  int _liveCount = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(AppConstants.sponsoredSlideInterval * 2, (_) {
      if (mounted && _liveCount > 1) {
        setState(() => _index = (_index + 1) % _liveCount);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PartnerAdModel>>(
      stream: _stream,
      builder: (context, snap) {
        final ads = (snap.data ?? const <PartnerAdModel>[])
            .where((a) => a.isLive)
            .toList();
        _liveCount = ads.length;
        if (ads.isEmpty) return const SizedBox.shrink();
        final ad = ads[_index % ads.length];
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              if (ad.imageUrl.isNotEmpty)
                SizedBox(
                  width: 96,
                  height: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: ad.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ad.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (ad.link.isNotEmpty)
                        Text(
                          ad.link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Text(
                  'Ad',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small promo pill (Sponsored / Hot).
class _PromoTag extends StatelessWidget {
  const _PromoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.coral,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
