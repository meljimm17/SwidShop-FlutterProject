import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/bid_model.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../shared/transaction_chat_screen.dart';

/// Real-time auction room for one item (Phase 3.6).
///
/// Bids go through [FirestoreService.placeBid] (transaction-guarded single
/// winner). When the timer hits zero the auction closes idempotently via
/// [FirestoreService.closeAuctionIfEnded], like the seller monitor.
class LiveBiddingScreen extends StatefulWidget {
  const LiveBiddingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<LiveBiddingScreen> createState() => _LiveBiddingScreenState();
}

class _LiveBiddingScreenState extends State<LiveBiddingScreen> {
  final _firestore = FirestoreService();
  final _bidCtrl = TextEditingController();
  late final Stream<ListingModel?> _listing = _firestore.streamListing(
    widget.listingId,
  );
  late final Stream<List<BidModel>> _bids = _firestore.streamBids(
    widget.listingId,
  );

  Timer? _ticker;
  bool _bidding = false;
  bool _closeAttempted = false;
  bool _closing = false;
  String? _txnId;
  String? _inputError;

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
    _bidCtrl.dispose();
    super.dispose();
  }

  double _minimumFor(ListingModel l) {
    final current = l.currentHighestBid ?? l.startingBid ?? 0;
    final rawStep = l.minIncrement ?? 1;
    final step = rawStep <= 0 ? 1.0 : rawStep.toDouble();
    return current + step;
  }

  Future<void> _bid(ListingModel l) async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty) return;
    final amount = double.tryParse(_bidCtrl.text.trim());
    final minimum = _minimumFor(l);
    if (amount == null || amount < minimum) {
      setState(() {
        _inputError =
            'Enter at least ${AppUtils.formatCurrency(minimum)} to outbid.';
      });
      return;
    }
    setState(() {
      _bidding = true;
      _inputError = null;
    });
    try {
      // Remember who gets outbid before our write moves the lead.
      final previousLead = l.highestBidderId;
      await _firestore.placeBid(
        listingId: l.listingId,
        bidderId: uid,
        amount: amount,
      );
      _bidCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bid placed — you lead!')));
      // Notify the outbid party + the seller (fire-and-forget).
      // ignore: unawaited_futures
      _notifyOutbid(l, previousLead: previousLead, winnerId: uid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inputError = e is StateError ? e.message : 'Bid failed. Try again.';
      });
    } finally {
      if (mounted) setState(() => _bidding = false);
    }
  }

  Future<void> _notifyOutbid(
    ListingModel l, {
    required String previousLead,
    required String winnerId,
  }) async {
    final price = AppUtils.formatCurrency(l.currentHighestBid ?? l.startingBid);
    if (previousLead.isNotEmpty && previousLead != winnerId) {
      try {
        await _firestore.addNotification(
          previousLead,
          NotificationModel(
            type: NotificationType.outbid,
            message: 'You were outbid on "${l.title}" ($price).',
            relatedId: 'listing:${l.listingId}',
          ),
        );
      } catch (e) {
        debugPrint('notifyOutbid: $e');
      }
    }
    if (l.sellerId.isNotEmpty) {
      try {
        await _firestore.addNotification(
          l.sellerId,
          NotificationModel(
            type: NotificationType.bidReceived,
            message: 'New bid on "${l.title}" ($price).',
            relatedId: 'listing:${l.listingId}',
          ),
        );
      } catch (e) {
        debugPrint('notifyBidReceived: $e');
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Live Bidding'),
      body: StreamBuilder<ListingModel?>(
        stream: _listing,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final listing = snap.data;
          if (listing == null) {
            return const Center(child: Text('Listing not found'));
          }
          _maybeClose(listing);
          final endedByTime =
              listing.auctionEndAt != null &&
              !listing.auctionEndAt!.isAfter(DateTime.now());
          final closed = listing.status != ListingStatus.active || endedByTime;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                listing.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _heroBid(listing),
              const SizedBox(height: 12),
              _countdown(listing),
              const SizedBox(height: 20),
              if (closed)
                _closedState(context, listing, uid)
              else if (listing.sellerId == uid)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'This is your auction — manage it from the Seller Centre.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray),
                    ),
                  ),
                )
              else ...[
                _bidBox(listing),
                const SizedBox(height: 20),
                _history(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _heroBid(ListingModel l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        children: [
          const Text(
            'Current highest bid',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            AppUtils.formatCurrency(l.currentHighestBid ?? l.startingBid),
            style: const TextStyle(
              color: AppColors.amber,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l.bidCount} bid${l.bidCount == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _countdown(ListingModel l) {
    final ended =
        l.auctionEndAt != null && !l.auctionEndAt!.isAfter(DateTime.now());
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.timer_outlined,
          color: ended
              ? AppColors.gray
              : (AppUtils.isEndingSoon(l.auctionEndAt)
                    ? AppColors.amber
                    : AppColors.ink),
        ),
        const SizedBox(width: 6),
        Text(
          ended ? 'Auction ended' : AppUtils.timeRemaining(l.auctionEndAt),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ],
    );
  }

  Widget _bidBox(ListingModel l) {
    final minimum = _minimumFor(l);
    final rawStep = l.minIncrement ?? 1;
    final step = rawStep <= 0 ? 1.0 : rawStep.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                child: ChoiceChip(
                  label: Text('+${AppUtils.formatCurrency(step * i)}'),
                  selected: false,
                  showCheckmark: false,
                  onSelected: (_) {
                    _bidCtrl.text = (minimum + step * (i - 1)).toStringAsFixed(
                      0,
                    );
                    setState(() => _inputError = null);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bidCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Your bid (min ${AppUtils.formatCurrency(minimum)})',
            prefixIcon: const Icon(Icons.gavel_outlined),
            errorText: _inputError,
          ),
          onChanged: (_) {
            if (_inputError != null) setState(() => _inputError = null);
          },
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Place Bid',
          loading: _bidding,
          onPressed: _bidding ? null : () => _bid(l),
        ),
      ],
    );
  }

  Widget _history() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bid history',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<BidModel>>(
          stream: _bids,
          builder: (context, snap) {
            final bids = snap.data ?? const <BidModel>[];
            if (bids.isEmpty) {
              return const Text(
                'No bids yet — be the first.',
                style: TextStyle(color: AppColors.gray),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < bids.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        if (i == 0)
                          const Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                            color: AppColors.amber,
                          )
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Expanded(child: UserNameText(bids[i].bidderId)),
                        Text(
                          AppUtils.formatCurrency(bids[i].amount),
                          style: TextStyle(
                            fontWeight: i == 0
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _closedState(BuildContext context, ListingModel l, String uid) {
    final finalizing = l.status == ListingStatus.active;
    final won =
        !finalizing && l.highestBidderId.isNotEmpty && l.highestBidderId == uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_closing)
          const Center(child: CircularProgressIndicator())
        else if (finalizing)
          const Center(
            child: Text(
              'This auction has ended. The final result is being processed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gray),
            ),
          )
        else if (won) ...[
          const Center(
            child: Text(
              'You won this auction!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Open Deal Chat',
            icon: Icons.chat_bubble_outline,
            onPressed: () async {
              var id = _txnId;
              id ??= (await _firestore.findSellerTransactionForListing(
                sellerId: l.sellerId,
                listingId: l.listingId,
              ))?.transactionId;
              if (!context.mounted) return;
              if (id == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('The deal is still being created.'),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransactionChatScreen(transactionId: id!),
                ),
              );
            },
          ),
        ] else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (l.status == ListingStatus.expired && l.hasBids)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Reserve not met — this item went unsold.',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const Center(
                child: Text(
                  'This auction has ended.',
                  style: TextStyle(color: AppColors.gray),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
