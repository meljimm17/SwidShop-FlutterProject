import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/bid_model.dart';
import '../../models/listing_model.dart';
import '../../models/swap_offer_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../shared/rate_sheet.dart';
import '../shared/transaction_chat_screen.dart';
import 'listing_detail_screen.dart';
import 'live_bidding_screen.dart';

/// Activity tab selection (deep-linkable from notifications).
enum ActivityTab { bids, swaps, purchases }

/// The customer's Bids, Swaps and Purchases in one place (Phase 3.10).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.initialTab = ActivityTab.bids});

  final ActivityTab initialTab;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab.index);
  final _firestore = FirestoreService();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(
        title: 'Activity',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coral,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.coral,
          tabs: const [
            Tab(text: 'Bids'),
            Tab(text: 'Swaps'),
            Tab(text: 'Purchases'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _BidsTab(firestore: _firestore),
          _SwapsTab(firestore: _firestore),
          _PurchasesTab(firestore: _firestore),
        ],
      ),
    );
  }
}

/// Joins a listing doc for display; falls back to a snapshot title.
class ActivityListing extends StatelessWidget {
  const ActivityListing({
    super.key,
    required this.listingId,
    required this.fallbackTitle,
    required this.fallbackImage,
    required this.onTap,
    this.trailing,
  });

  final String listingId;
  final String fallbackTitle;
  final String fallbackImage;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ListingModel?>(
      future: FirestoreService().getListing(listingId),
      builder: (context, snap) {
        final l = snap.data;
        return AppCardWrapper(
          onTap: onTap,
          child: Row(
            children: [
              ListingThumb(
                url: l != null && l.images.isNotEmpty
                    ? l.images.first
                    : fallbackImage,
                size: 56,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.title ?? fallbackTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (l != null)
                      TypeBadge(l.type)
                    else
                      const Text(
                        'Listing unavailable',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.gray),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BidsTab extends StatelessWidget {
  const _BidsTab({required this.firestore});

  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return StreamBuilder<List<BidModel>>(
      stream: firestore.streamBidsForBidder(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final bids = snap.data ?? const <BidModel>[];
        if (bids.isEmpty) {
          return const _EmptyWhat('No bids yet.');
        }
        final ids = bids.map((b) => b.listingId).toSet().toList();
        return FutureBuilder<Map<String, ListingModel>>(
          future: _listingMap(ids),
          builder: (context, lsnap) {
            if (lsnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final map = lsnap.data ?? const <String, ListingModel>{};
            final active = <BidModel>[];
            final won = <BidModel>[];
            final outbid = <BidModel>[];
            final closed = <BidModel>[];
            for (final b in bids) {
              final l = map[b.listingId];
              if (l == null || l.status == ListingStatus.active) {
                if (l != null &&
                    l.hasBids &&
                    l.highestBidderId.isNotEmpty &&
                    l.highestBidderId != uid) {
                  outbid.add(b);
                } else {
                  active.add(b);
                }
              } else if (l.status == ListingStatus.sold &&
                  l.highestBidderId == uid) {
                won.add(b);
              } else if (l.status == ListingStatus.sold) {
                outbid.add(b);
              } else {
                closed.add(b);
              }
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _bidSection(context, 'Active Bids', active, map, uid),
                _bidSection(context, 'Won Auctions', won, map, uid),
                _bidSection(context, 'Outbid', outbid, map, uid),
                _bidSection(context, 'Closed', closed, map, uid),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, ListingModel>> _listingMap(List<String> ids) async {
    final entries = await Future.wait(
      ids.map((id) async {
        try {
          final l = await firestore.getListing(id);
          return MapEntry(id, l);
        } catch (_) {
          return const MapEntry('', null);
        }
      }),
    );
    return {
      for (final e in entries)
        if (e.key.isNotEmpty && e.value != null) e.key: e.value!,
    };
  }

  Widget _bidSection(
    BuildContext context,
    String title,
    List<BidModel> bids,
    Map<String, ListingModel> map,
    String uid,
  ) {
    if (bids.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            '$title (${bids.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.gray,
              fontSize: 13,
            ),
          ),
        ),
        for (final b in bids)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _bidRow(context, b, map[b.listingId], uid),
          ),
      ],
    );
  }

  Widget _bidRow(
    BuildContext context,
    BidModel bid,
    ListingModel? listing,
    String uid,
  ) {
    final l = listing;
    final live = l != null && l.status == ListingStatus.active;
    final leading = l != null &&
        l.highestBidderId.isNotEmpty &&
        l.highestBidderId == uid;
    if (l == null) {
      return AppCardWrapper(
        child: Row(
          children: [
            const ListingThumb(url: '', size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'My bid ${AppUtils.formatCurrency(bid.amount)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return AppCardWrapper(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => live
                ? LiveBiddingScreen(listingId: l.listingId)
                : ListingDetailScreen(listingId: l.listingId),
          ),
        );
      },
      child: Row(
        children: [
          ListingThumb(
            url: l.images.isNotEmpty ? l.images.first : '',
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'My bid ${AppUtils.formatCurrency(bid.amount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.coral,
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 8),
                      Text(
                        leading ? 'LEADING' : 'OUTBID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: leading
                              ? AppColors.teal
                              : AppColors.red,
                        ),
                      ),
                    ],
                  ],
                ),
                if (live)
                  Text(
                    AppUtils.timeRemaining(l.auctionEndAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
              ],
            ),
          ),
          if (live)
            const Icon(Icons.chevron_right, color: AppColors.gray),
        ],
      ),
    );
  }
}

class _SwapsTab extends StatelessWidget {
  const _SwapsTab({required this.firestore});

  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return StreamBuilder<List<SwapOfferModel>>(
      stream: firestore.streamOffersByUser(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = snap.data ?? const <SwapOfferModel>[];
        if (offers.isEmpty) {
          return const _EmptyWhat('No swap offers yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: offers.length,
          itemBuilder: (context, i) {
            final o = offers[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ActivityListing(
                listingId: o.listingId,
                fallbackTitle: 'Swap target',
                fallbackImage: '',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ListingDetailScreen(listingId: o.listingId),
                  ),
                ),
                trailing: StatusPill(
                  o.status == SwapOfferStatus.pending
                      ? 'Pending'
                      : o.status == SwapOfferStatus.accepted
                          ? 'Accepted'
                          : 'Declined',
                  color: o.status == SwapOfferStatus.pending
                      ? AppColors.amber
                      : o.status == SwapOfferStatus.accepted
                          ? AppColors.green
                          : AppColors.gray,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab({required this.firestore});

  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    final myUid = uid;
    return StreamBuilder<List<TransactionModel>>(
      stream: firestore.streamBuyerTransactions(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final txns = snap.data ?? const <TransactionModel>[];
        if (txns.isEmpty) {
          return const _EmptyWhat('No purchases yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: txns.length,
          itemBuilder: (context, i) {
            final t = txns[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ActivityListing(
                listingId: t.listingId,
                fallbackTitle: t.listingTitle,
                fallbackImage: t.listingImage,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TransactionChatScreen(transactionId: t.transactionId),
                  ),
                ),
                trailing: _TxnTrailing(txn: t, myUid: myUid),
              ),
            );
          },
        );
      },
    );
  }
}

/// Status pill + conditional Rate action (completed + not yet rated).
class _TxnTrailing extends StatelessWidget {
  const _TxnTrailing({required this.txn, required this.myUid});

  final TransactionModel txn;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusPill.transaction(txn.status),
        if (txn.status == TransactionStatus.completed)
          FutureBuilder<bool>(
            future: RateSheet.alreadyRated(txn.transactionId, myUid),
            builder: (context, snap) {
              if (snap.data == false) {
                return TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: AppColors.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (_) => RateSheet(
                      transactionId: txn.transactionId,
                      ratedUserId: txn.sellerId,
                      ratedName: '',
                    ),
                  ),
                  child: const Text('Rate'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
      ],
    );
  }
}

class _EmptyWhat extends StatelessWidget {
  const _EmptyWhat(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: const TextStyle(color: AppColors.gray)),
    );
  }
}
