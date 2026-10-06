import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../admin/admin_users_screen.dart';
import '../seller/monitor_bidding_screen.dart';
import '../seller/swap_offers_screen.dart';
import '../shared/transaction_chat_screen.dart';
import 'activity_screen.dart';
import 'listing_detail_screen.dart';
import 'profile_screen.dart';

/// relatedId convention written by every notifier:
/// `<kind>:<id>` with kind = listing | transaction | offer.
({String kind, String id}) parseRelatedId(String relatedId) {
  final i = relatedId.indexOf(':');
  if (i <= 0) return (kind: '', id: relatedId);
  return (kind: relatedId.substring(0, i), id: relatedId.substring(i + 1));
}

/// Notification filter tabs (Phase 3.9).
enum NotificationFilter { all, bids, swaps, orders }

/// Central feed: outbid warnings, swaps, sales and order updates.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _firestore = FirestoreService();
  NotificationFilter _filter = NotificationFilter.all;

  bool _matches(NotificationModel n) {
    switch (_filter) {
      case NotificationFilter.all:
        return true;
      case NotificationFilter.bids:
        return n.type == NotificationType.outbid ||
            n.type == NotificationType.bidReceived;
      case NotificationFilter.swaps:
        return n.type == NotificationType.swapOffer ||
            n.type == NotificationType.swapAccepted;
      case NotificationFilter.orders:
        return n.type == NotificationType.transactionUpdate ||
            n.type == NotificationType.message ||
            n.type == NotificationType.rating;
    }
  }

  Future<void> _open(NotificationModel n) async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isNotEmpty && !n.read) {
      // Fire-and-forget: the stream rebuild marks it read.
      // ignore: unawaited_futures
      _firestore.markNotificationRead(uid, n.notificationId);
    }
    if (!mounted) return;
    final role = context.read<AuthProvider>().profile?.role;
    openNotificationTarget(context, n, role: role);
  }

  Future<void> _markAllRead() async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      await _firestore.markAllNotificationsRead(uid);
    } catch (e) {
      debugPrint('markAllNotificationsRead: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Notifications'),
      body: uid.isEmpty
          ? const Center(child: Text('Log in to see notifications.'))
          : StreamBuilder<List<NotificationModel>>(
              stream: _firestore.streamNotifications(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items =
                    (snap.data ?? const <NotificationModel>[])
                        .where(_matches)
                        .toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  );
                }
                final now = DateTime.now();
                final today = <NotificationModel>[];
                final earlier = <NotificationModel>[];
                for (final n in items) {
                  final c = n.createdAt;
                  if (c != null &&
                      c.year == now.year &&
                      c.month == now.month &&
                      c.day == now.day) {
                    today.add(n);
                  } else {
                    earlier.add(n);
                  }
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _chips()),
                        TextButton(
                          onPressed: _markAllRead,
                          child: const Text('Mark all read'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (today.isNotEmpty) ...[
                      _section('Today'),
                      for (final n in today) _tile(n),
                    ],
                    if (earlier.isNotEmpty) ...[
                      _section('Earlier'),
                      for (final n in earlier) _tile(n),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _chips() {
    Widget chip(String label, NotificationFilter f) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = f),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All', NotificationFilter.all),
          chip('Bids & Auctions', NotificationFilter.bids),
          chip('Swaps', NotificationFilter.swaps),
          chip('Orders', NotificationFilter.orders),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.gray,
            fontSize: 13,
          ),
        ),
      );

  Widget _tile(NotificationModel n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        onTap: () => _open(n),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: n.read ? Colors.transparent : AppColors.coral,
              ),
            ),
            const SizedBox(width: 10),
            _thumb(n),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.message,
                    style: TextStyle(
                      fontWeight:
                          n.read ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.createdAt == null
                        ? ''
                        : timeago.format(n.createdAt!),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.gray),
          ],
        ),
      ),
    );
  }

  /// Listing thumbnail for listing-linked notifications (mockup rows).
  /// Other kinds keep the text-only row — no fake imagery.
  Widget _thumb(NotificationModel n) {
    final link = parseRelatedId(n.relatedId);
    if (link.kind != 'listing' || link.id.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FutureBuilder<ListingModel?>(
        future: FirestoreService().getListing(link.id),
        builder: (context, snap) {
          final url = snap.data != null && snap.data!.images.isNotEmpty
              ? snap.data!.images.first
              : '';
          if (url.isEmpty) return const SizedBox.shrink();
          return ListingThumb(url: url, size: 44);
        },
      ),
    );
  }
}

/// Routes a notification tap to the related screen. Shared entry point so
/// the bell, lists and future pushes all land in the same place.
void openNotificationTarget(
  BuildContext context,
  NotificationModel n, {
  UserRole? role,
}) {
  final link = parseRelatedId(n.relatedId);
  Widget? next;
  switch (n.type) {
    case NotificationType.outbid:
      if (link.id.isNotEmpty) {
        next = ListingDetailScreen(listingId: link.id);
      }
    case NotificationType.bidReceived:
      if (link.id.isNotEmpty) {
        next = MonitorBiddingScreen(listingId: link.id);
      }
    case NotificationType.swapOffer:
      // Sellers open their queue; buyers open their Activity swaps tab.
      next = (role?.canSell ?? false)
          ? const SwapOffersScreen()
          : const ActivityScreen(initialTab: ActivityTab.swaps);
    case NotificationType.swapAccepted:
    case NotificationType.transactionUpdate:
    case NotificationType.message:
      if (link.id.isNotEmpty) {
        next = TransactionChatScreen(transactionId: link.id);
      }
    case NotificationType.rating:
      next = const ProfileScreen();
    case NotificationType.system:
      // Role-change decisions open Profile (role + request status);
      // auction end-time changes open the listing.
      if (link.kind == 'role') next = const ProfileScreen();
      if (link.kind == 'listing' && link.id.isNotEmpty) {
        next = ListingDetailScreen(listingId: link.id);
      }
      if (link.kind == 'trust' && link.id.isNotEmpty) {
        if (role == UserRole.admin) {
          openAdminUserDetail(context, link.id);
          return;
        }
        next = const ProfileScreen();
      }
  }
  // Sellers tapping a listing link land on the auction monitor instead.
  if (next is ListingDetailScreen &&
      (role?.canSell ?? false) &&
      n.type == NotificationType.bidReceived &&
      link.id.isNotEmpty) {
    next = MonitorBiddingScreen(listingId: link.id);
  }
  if (next == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => next!));
}
