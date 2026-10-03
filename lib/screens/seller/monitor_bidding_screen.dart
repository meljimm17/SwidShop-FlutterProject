import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/bid_model.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/primary_button.dart';
import '../shared/transaction_chat_screen.dart';

/// Seller's auctions (live first, then ended) → [MonitorBiddingScreen].
class AuctionsScreen extends StatefulWidget {
  const AuctionsScreen({super.key});

  @override
  State<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends State<AuctionsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  @override
  Widget build(BuildContext context) {
    final seller = context.watch<SellerProvider>();
    final auctions =
        seller.listings.where((l) => l.type == ListingType.bid).toList()
          ..sort((a, b) {
            final aLive = a.status == ListingStatus.active ? 0 : 1;
            final bLive = b.status == ListingStatus.active ? 0 : 1;
            if (aLive != bLive) return aLive - bLive;
            return (a.auctionEndAt ?? DateTime(0)).compareTo(
              b.auctionEndAt ?? DateTime(0),
            );
          });

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        title: const Text('Auctions'),
      ),
      body: seller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : auctions.isEmpty
          ? const EmptyState(
              icon: Icons.gavel_rounded,
              title: 'No auctions yet',
              message: 'Post a listing with the Bid option to start one.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: auctions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final l = auctions[i];
                final live = l.status == ListingStatus.active;
                return OutlineCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MonitorBiddingScreen(listingId: l.listingId),
                    ),
                  ),
                  child: Row(
                    children: [
                      ListingThumb(
                        url: l.images.isNotEmpty ? l.images.first : null,
                        size: 56,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              live
                                  ? AppUtils.timeRemaining(l.auctionEndAt)
                                  : 'Ended',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: live ? AppColors.amber : AppColors.gray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppUtils.formatCurrency(l.displayPrice),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.coral,
                            ),
                          ),
                          const SizedBox(height: 4),
                          StatusPill.listing(l.status),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Live view of one auction: highest bid, bidder count, countdown and the
/// bid log. When the timer hits zero it closes the auction (idempotently —
/// the Cloud Function may also do it) and shows the winner.
class MonitorBiddingScreen extends StatefulWidget {
  const MonitorBiddingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<MonitorBiddingScreen> createState() => _MonitorBiddingScreenState();
}

class _MonitorBiddingScreenState extends State<MonitorBiddingScreen> {
  final _firestore = FirestoreService();
  late final Stream<ListingModel?> _listing = _firestore.streamListing(
    widget.listingId,
  );
  late final Stream<List<BidModel>> _bids = _firestore.streamBids(
    widget.listingId,
  );

  Timer? _ticker;
  bool _closing = false;
  bool _closeAttempted = false;
  String? _txnId;
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Runs once when an active auction's end time has passed.
  void _maybeClose(ListingModel l) {
    final end = l.auctionEndAt;
    if (_closeAttempted ||
        l.status != ListingStatus.active ||
        end == null ||
        end.isAfter(DateTime.now())) {
      return;
    }
    _closeAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _closing = true);
      try {
        _txnId = await _firestore.closeAuctionIfEnded(l.listingId);
      } catch (e) {
        debugPrint('closeAuctionIfEnded: $e');
      } finally {
        if (mounted) setState(() => _closing = false);
      }
    });
  }

  Future<void> _messageWinner(ListingModel l) async {
    setState(() => _openingChat = true);
    try {
      var id = _txnId;
      if (id == null) {
        final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
        id = (await _firestore.findSellerTransactionForListing(
          sellerId: uid,
          listingId: l.listingId,
        ))?.transactionId;
      }
      if (!mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The deal is still being created.')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionChatScreen(transactionId: id!),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        title: const Text('Monitor bidding'),
      ),
      body: StreamBuilder<ListingModel?>(
        stream: _listing,
        builder: (context, lSnap) {
          final listing = lSnap.data;
          if (listing == null) {
            return lSnap.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : const EmptyState(
                    icon: Icons.search_off,
                    title: 'Listing not found',
                  );
          }
          _maybeClose(listing);
          return StreamBuilder<List<BidModel>>(
            stream: _bids,
            builder: (context, bSnap) =>
                _body(listing, bSnap.data ?? const <BidModel>[]),
          );
        },
      ),
    );
  }

  Widget _body(ListingModel l, List<BidModel> bidsByAmount) {
    final top = bidsByAmount.isEmpty ? null : bidsByAmount.first;
    final bidders = bidsByAmount.map((b) => b.bidderId).toSet().length;
    final remaining = (l.auctionEndAt ?? DateTime.now()).difference(
      DateTime.now(),
    );
    final ended = l.status != ListingStatus.active || remaining.isNegative;
    final log = [...bidsByAmount]
      ..sort(
        (a, b) => (b.placedAt ?? DateTime.now()).compareTo(
          a.placedAt ?? DateTime.now(),
        ),
      );
    final highest = top?.amount ?? l.currentHighestBid;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            ListingThumb(
              url: l.images.isNotEmpty ? l.images.first : null,
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Starts at ${AppUtils.formatCurrency(l.startingBid)}'
                    ' · +${AppUtils.formatCurrency(l.minIncrement)} min',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: ended
              ? _settledPanel(l, top)
              : _livePanel(remaining, highest, bidders),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Bid log',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            if (!ended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: AppColors.red),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.red,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Text(
              '${log.length} bid${log.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.gray, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (log.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.gavel_rounded,
              title: 'No bids yet',
              message: 'New bids appear here instantly.',
            ),
          )
        else
          OutlineCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < log.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 60, color: AppColors.line),
                  _BidRow(bid: log[i], isTop: log[i].bidId == top?.bidId),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _livePanel(Duration remaining, double? highest, int bidders) {
    final urgent = remaining.inHours < 1;
    return Container(
      key: const ValueKey('live'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        children: [
          const Text(
            'ENDS IN',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppUtils.formatCountdown(remaining),
            style: TextStyle(
              color: urgent ? AppColors.amber : Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Highest bid',
                  highest == null
                      ? 'No bids'
                      : AppUtils.formatCurrency(highest),
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(child: _metric('Bidders', '$bidders')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );

  Widget _settledPanel(ListingModel l, BidModel? top) {
    if (_closing) {
      return const Padding(
        key: ValueKey('closing'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (top == null) {
      return OutlineCard(
        key: const ValueKey('nobids'),
        child: const Row(
          children: [
            Icon(Icons.hourglass_disabled_outlined, color: AppColors.gray),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Auction ended without bids. The listing moved to Expired.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const ValueKey('winner'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events_outlined, color: AppColors.amber),
              SizedBox(width: 6),
              Text(
                'Auction closed',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          UserLookup(
            uid: top.bidderId,
            builder: (context, user) => Column(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.mist,
                  backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                      ? NetworkImage(user!.photoUrl)
                      : null,
                  child: (user?.photoUrl.isNotEmpty ?? false)
                      ? null
                      : const Icon(Icons.person_outline, color: AppColors.gray),
                ),
                const SizedBox(height: 8),
                Text(
                  (user?.name.isNotEmpty ?? false) ? user!.name : 'Winner',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Final hammer price',
            style: TextStyle(fontSize: 12.5, color: AppColors.gray),
          ),
          Text(
            AppUtils.formatCurrency(top.amount),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.coral,
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Message winner',
            icon: Icons.chat_bubble_outline,
            loading: _openingChat,
            onPressed: () => _messageWinner(l),
          ),
        ],
      ),
    );
  }
}

class _BidRow extends StatelessWidget {
  const _BidRow({required this.bid, required this.isTop});

  final BidModel bid;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          UserLookup(
            uid: bid.bidderId,
            builder: (context, user) => CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.mist,
              backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                  ? NetworkImage(user!.photoUrl)
                  : null,
              child: (user?.photoUrl.isNotEmpty ?? false)
                  ? null
                  : const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: AppColors.gray,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserNameText(
                  bid.bidderId,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  bid.placedAt == null
                      ? 'just now'
                      : timeago.format(bid.placedAt!),
                  style: const TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ],
            ),
          ),
          if (isTop) ...[
            const StatusPill('Highest', color: AppColors.amber),
            const SizedBox(width: 8),
          ],
          Text(
            AppUtils.formatCurrency(bid.amount),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isTop ? AppColors.coral : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
