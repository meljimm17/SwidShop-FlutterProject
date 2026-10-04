import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../customer/listing_detail_screen.dart';
import 'admin_gate.dart';

/// Moderate listings: remove violations, clear flags (Phase 4.3).
///
/// "Flagged" = has at least one pending report (reports collection, not a
/// field on the listing). Removing sets status='removed', which instantly
/// drops the item from every customer query (all filter status=='active').
class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  final _firestore = FirestoreService();
  ListingType? _type;
  int _visible = 25;

  static const _page = 25;

  Future<void> _remove(ListingModel listing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove this listing?'),
        content: Text(
          '"${listing.title}" disappears from Home, Search and every feed immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _firestore.updateListing(
        listing.listingId,
        {'status': ListingStatus.removed.value},
      );
    } catch (e) {
      debugPrint('removeListing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  /// Dismisses every pending report against the listing (clears its flag).
  Future<void> _clearFlags(
    ListingModel listing,
    List<ReportModel> pending,
  ) async {
    final related = pending
        .where((r) =>
            r.targetType == ReportTargetType.listing &&
            r.targetId == listing.listingId)
        .toList();
    if (related.isEmpty) return;
    try {
      await Future.wait(
        related.map(
          (r) => _firestore.updateReportStatus(
            r.reportId,
            ReportStatus.dismissed,
          ),
        ),
      );
    } catch (e) {
      debugPrint('clearFlags: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: const TopAppBar(title: 'Manage Listings'),
        body: StreamBuilder<List<ReportModel>>(
          stream: _firestore.streamReportsByStatus(ReportStatus.pending),
          builder: (context, reportSnap) {
            final pending = reportSnap.data ?? const <ReportModel>[];
            final flaggedIds = {
              for (final r in pending)
                if (r.targetType == ReportTargetType.listing) r.targetId,
            };
            return StreamBuilder<List<ListingModel>>(
              stream: _firestore.streamAllListings(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snap.data ?? const <ListingModel>[];
                if (_type != null) {
                  items = items.where((l) => l.type == _type).toList();
                }
                // Flagged first, then newest.
                items.sort((a, b) {
                  final af = flaggedIds.contains(a.listingId) ? 0 : 1;
                  final bf = flaggedIds.contains(b.listingId) ? 0 : 1;
                  if (af != bf) return af.compareTo(bf);
                  final ac = a.createdAt;
                  final bc = b.createdAt;
                  if (ac == null && bc == null) return 0;
                  if (ac == null) return 1;
                  if (bc == null) return -1;
                  return bc.compareTo(ac);
                });
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No listings.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  );
                }
                final shown = items.take(_visible).toList();
                return Column(
                  children: [
                    _chips(),
                    if (flaggedIds.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '${flaggedIds.length} flagged item${flaggedIds.length == 1 ? '' : 's'} need${flaggedIds.length == 1 ? 's' : ''} review.',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: shown.length +
                            (items.length > _visible ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= shown.length) {
                            return Center(
                              child: TextButton(
                                onPressed: () => setState(
                                  () => _visible += _page,
                                ),
                                child: Text(
                                  'Load more (${items.length - _visible} left)',
                                ),
                              ),
                            );
                          }
                          final l = shown[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _row(
                              l,
                              flagged: flaggedIds.contains(l.listingId),
                              pending: pending,
                            ),
                          );                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _chips() {
    Widget chip(String label, ListingType? type) {
      final selected = _type == type;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() {
            _type = selected ? null : type;
            _visible = _page;
          }),
          selectedColor: AppColors.coral,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.coral : AppColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          chip('All', null),
          chip('Buy Now', ListingType.buyNow),
          chip('Bidding', ListingType.bid),
          chip('Swap', ListingType.swap),
        ],
      ),
    );
  }

  Widget _row(
    ListingModel listing, {
    required bool flagged,
    required List<ReportModel> pending,
  }) {
    return AppCardWrapper(
      child: Row(
        children: [
          ListingThumb(
            url: listing.images.isNotEmpty ? listing.images.first : '',
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UserNameText(
                      listing.sellerId,
                      style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                      ),
                    ),
                    TypeBadge(listing.type),
                    StatusPill(
                      listing.status.value,
                      color: listing.status == ListingStatus.active
                          ? AppColors.green
                          : AppColors.gray,
                    ),
                    if (flagged)
                      const Icon(
                        Icons.flag,
                        size: 16,
                        color: AppColors.red,
                      ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.gray),
            onSelected: (action) {
              switch (action) {
                case 'view':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(
                        listingId: listing.listingId,
                      ),
                    ),
                  );
                case 'remove':
                  _remove(listing);
                case 'clear':
                  _clearFlags(listing, pending);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view', child: Text('View')),
              if (flagged)
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear flags'),
                ),
              if (listing.status == ListingStatus.active)
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove Listing'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
