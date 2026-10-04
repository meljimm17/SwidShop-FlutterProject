import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../providers/admin_provider.dart';
import '../customer/listing_detail_screen.dart';
import 'admin_widgets.dart';

/// Listings tab: search, type pills with live counts, flagged banner and
/// moderation menu (Phase 4.3).
///
/// "Flagged" = at least one pending report on the listing. Removing sets
/// status='removed', which drops it from every customer feed at once.
class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  ListingType? _type;
  ListingStatus? _status;
  bool _flaggedOnly = false;
  int _visible = 20;

  static const _page = 20;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStatus() async {
    final picked = await showModalBottomSheet<(ListingStatus?,)>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (d) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter by status',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final (value, label) in [
              (null, 'Any status'),
              (ListingStatus.active, 'Active'),
              (ListingStatus.sold, 'Sold'),
              (ListingStatus.expired, 'Expired'),
              (ListingStatus.removed, 'Removed'),
            ])
              ListTile(
                title: Text(label),
                trailing: _status == value
                    ? const Icon(Icons.check, color: AppColors.coralDeep)
                    : null,
                onTap: () => Navigator.of(d).pop((value,)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _status = picked.$1;
        _visible = _page;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final flagged = a.flaggedListingIds;
    final types = AdminStats.typeCounts(a.listings);

    var items = a.listings;
    if (_type != null) items = items.where((l) => l.type == _type).toList();
    if (_status != null) {
      items = items.where((l) => l.status == _status).toList();
    }
    if (_flaggedOnly) {
      items = items.where((l) => flagged.contains(l.listingId)).toList();
    }
    if (_query.isNotEmpty) {
      items = items
          .where(
            (l) =>
                l.title.toLowerCase().contains(_query) ||
                l.listingId.toLowerCase().contains(_query) ||
                a.nameOf(l.sellerId).toLowerCase().contains(_query),
          )
          .toList();
    }
    // Flagged first, then newest (stream order).
    items = [
      ...items.where((l) => flagged.contains(l.listingId)),
      ...items.where((l) => !flagged.contains(l.listingId)),
    ];
    final shown = items.take(_visible).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: AdminSearchField(
                  controller: _searchCtrl,
                  hint: 'Search listing ID, title, or seller…',
                  onChanged: (v) => setState(() {
                    _query = v.trim().toLowerCase();
                    _visible = _page;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: AppColors.surface,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _pickStatus,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Badge(
                      isLabelVisible: _status != null,
                      smallSize: 9,
                      backgroundColor: AppColors.coralDeep,
                      alignment: const AlignmentDirectional(0.45, -0.45),
                      child: const Icon(Icons.tune, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        PillRow<ListingType?>(
          selected: _type,
          onSelected: (t) => setState(() {
            _type = t;
            _visible = _page;
          }),
          options: [
            PillOption(null, 'All ${a.listings.length}'),
            PillOption(ListingType.bid, 'Bidding ${types[ListingType.bid]}'),
            PillOption(ListingType.swap, 'Swap ${types[ListingType.swap]}'),
            PillOption(
              ListingType.buyNow,
              'Buy Now ${types[ListingType.buyNow]}',
            ),
          ],
        ),
        if (flagged.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.coralDeep,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '${flagged.length} Flagged ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.coralDeep,
                      ),
                      children: const [
                        TextSpan(
                          text: 'listing reports to review',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                FilledButton(
                  onPressed: () => setState(() {
                    _flaggedOnly = !_flaggedOnly;
                    _visible = _page;
                  }),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coralDeep,
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_flaggedOnly ? 'SHOW ALL' : 'INSPECT'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No listings match.',
                style: TextStyle(color: AppColors.gray),
              ),
            ),
          ),
        for (final l in shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _ListingCard(
              listing: l,
              flaggedCount: AdminStats.pendingFor(a.reports, l.listingId),
            ),
          ),
        if (items.length > _visible)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _visible += _page),
              child: Text('Load more (${items.length - _visible} left)'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Showing ${shown.length} of ${items.length} listing${items.length == 1 ? '' : 's'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.gray,
            ),
          ),
        ),
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, required this.flaggedCount});

  final ListingModel listing;
  final int flaggedCount;

  String _typeText() {
    final l = listing;
    final price = l.displayPrice;
    switch (l.type) {
      case ListingType.swap:
        return l.swapWants.isEmpty ? 'Swap' : 'Swap (ISO: ${l.swapWants})';
      case ListingType.bid:
      case ListingType.buyNow:
        return price == null
            ? typeLabel(l.type)
            : '${typeLabel(l.type)} ${AppUtils.formatCurrency(price)}';
    }
  }

  String _meta(AdminProvider a) {
    final l = listing;
    final seller = a.nameOf(l.sellerId);
    if (l.type == ListingType.bid &&
        l.status == ListingStatus.active &&
        l.auctionEndAt != null &&
        l.auctionEndAt!.isAfter(DateTime.now())) {
      return '$seller • ${AppUtils.timeRemaining(l.auctionEndAt)}';
    }
    if (l.createdAt == null) return seller;
    return '$seller • ${timeago.format(l.createdAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final l = listing;
    final inactive = l.status != ListingStatus.active;
    return AdminCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      onTap: () => _view(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: inactive ? 0.6 : 1,
            child: TaggedThumb(
              url: l.images.isNotEmpty ? l.images.first : '',
              tag: AdminStats.shortCode('ID', l.listingId),
              width: 104,
              height: 104,
            ),
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
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: inactive ? AppColors.gray : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _meta(a),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SoftPill(
                      _typeText(),
                      color: inactive ? AppColors.gray : typeColor(l.type),
                      icon: typeIcon(l.type),
                    ),
                    StatusTag(status: l.status),
                    if (flaggedCount > 0)
                      SoftPill(
                        flaggedCount == 1
                            ? 'Flagged'
                            : 'Flagged ×$flaggedCount',
                        color: AppColors.red,
                        dot: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          _ListingMenu(listing: l, flagged: flaggedCount > 0),
        ],
      ),
    );
  }

  void _view(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ListingDetailScreen(listingId: listing.listingId),
    ),
  );
}

/// Listing status pill (Active · Sold · Expired · Removed).
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ListingStatus.active => ('Active', AppColors.green),
      ListingStatus.sold => ('Sold', AppColors.coral),
      ListingStatus.expired => ('Expired', AppColors.gray),
      ListingStatus.removed => ('Removed', AppColors.red),
    };
    return SoftPill(label, color: color, dot: true);
  }
}

class _ListingMenu extends StatelessWidget {
  const _ListingMenu({required this.listing, required this.flagged});

  final ListingModel listing;
  final bool flagged;

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Remove this listing?',
      message:
          '"${listing.title}" disappears from Home, Search and every feed '
          'immediately. Pending reports on it are closed as removed.',
      confirmLabel: 'Remove',
    );
    if (!ok || !context.mounted) return;
    final a = context.read<AdminProvider>();
    try {
      await a.firestore.updateListing(listing.listingId, {
        'status': ListingStatus.removed.value,
      });
      await Future.wait(
        a.pendingReports
            .where((r) => r.targetId == listing.listingId)
            .map(
              (r) => a.firestore.updateReportStatus(
                r.reportId,
                ReportStatus.removed,
              ),
            ),
      );
    } catch (e) {
      debugPrint('removeListing: $e');
      if (context.mounted) {
        showAdminError(context, 'Could not remove. Try again.');
      }
    }
  }

  Future<void> _clear(BuildContext context) async {
    final a = context.read<AdminProvider>();
    try {
      await Future.wait(
        a.pendingReports
            .where(
              (r) =>
                  r.targetType == ReportTargetType.listing &&
                  r.targetId == listing.listingId,
            )
            .map(
              (r) => a.firestore.updateReportStatus(
                r.reportId,
                ReportStatus.dismissed,
              ),
            ),
      );
    } catch (e) {
      debugPrint('clearFlags: $e');
      if (context.mounted) {
        showAdminError(context, 'Could not clear. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.ink),
      color: AppColors.surface,
      onSelected: (v) {
        switch (v) {
          case 'view':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ListingDetailScreen(listingId: listing.listingId),
              ),
            );
          case 'clear':
            _clear(context);
          case 'remove':
            _remove(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 20),
              SizedBox(width: 12),
              Text('View Listing'),
            ],
          ),
        ),
        if (flagged)
          const PopupMenuItem(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 20, color: AppColors.teal),
                SizedBox(width: 12),
                Text('Clear Flags', style: TextStyle(color: AppColors.teal)),
              ],
            ),
          ),
        if (listing.status != ListingStatus.removed) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: AppColors.red),
                SizedBox(width: 12),
                Text('Remove Listing', style: TextStyle(color: AppColors.red)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
