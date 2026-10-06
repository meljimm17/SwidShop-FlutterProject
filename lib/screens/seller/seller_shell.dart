import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../customer/profile_screen.dart';
import 'dashboard_screen.dart';
import 'my_listings_screen.dart';
import 'seller_messages_screen.dart';
import 'seller_orders_screen.dart';

/// Seller side of the app with bottom navigation:
/// Dashboard · Listings · Orders · Messages · Profile.
///
/// Root for `seller` accounts; `both` accounts push it from customer Home.
class SellerShell extends StatefulWidget {
  const SellerShell({super.key, this.initialTab = SellerTab.dashboard});

  final SellerTab initialTab;

  /// Switches the enclosing shell's tab (no-op outside a shell).
  static void goTo(BuildContext context, SellerTab tab) =>
      context.findAncestorStateOfType<_SellerShellState>()?._select(tab);

  @override
  State<SellerShell> createState() => _SellerShellState();
}

enum SellerTab { dashboard, listings, orders, messages, profile }

class _SellerShellState extends State<SellerShell> {
  late SellerTab _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
    // Client-side scheduler stand-in (functions never deploy): expire
    // boosts/features/plans, send fee reminders, apply overdue holds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
      if (uid.isEmpty) return;
      final firestore = FirestoreService();
      // ignore: unawaited_futures
      firestore.runSellerMaintenance(uid);
      _registerPushToken(firestore, uid);
    });
  }

  /// Saves this device's FCM token so fee reminders can be pushed.
  /// Best-effort: no permission / no Play services just means in-app only.
  Future<void> _registerPushToken(FirestoreService firestore, String uid) async {
    try {
      final token = await context.read<NotificationService>().init();
      if (token != null && token.isNotEmpty) {
        await firestore.saveFcmToken(uid, token);
      }
    } catch (e) {
      debugPrint('registerPushToken: $e');
    }
  }

  void _select(SellerTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    // Role changed by an admin while this was open (e.g. → Customer).
    final role = context.select<AuthProvider, UserRole?>(
      (a) => a.profile?.role,
    );
    if (role != null && !role.canSell) return const _NoSellerAccess();
    final seller = context.watch<SellerProvider>();
    final openOrders = seller.openOrders.length;

    return PopScope(
      // Back from another tab returns to Dashboard first.
      canPop: _tab == SellerTab.dashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(SellerTab.dashboard);
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: IndexedStack(
          index: _tab.index,
          children: const [
            SellerDashboardScreen(),
            MyListingsScreen(),
            SellerOrdersScreen(),
            SellerMessagesScreen(),
            ProfileScreen(embedded: true),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  _item(
                    SellerTab.dashboard,
                    Icons.storefront_outlined,
                    Icons.storefront,
                    'Dashboard',
                  ),
                  _item(
                    SellerTab.listings,
                    Icons.inventory_2_outlined,
                    Icons.inventory_2,
                    'Listings',
                  ),
                  _item(
                    SellerTab.orders,
                    Icons.receipt_long_outlined,
                    Icons.receipt_long,
                    'Orders',
                    badge: openOrders,
                  ),
                  _item(
                    SellerTab.messages,
                    Icons.chat_bubble_outline,
                    Icons.chat_bubble,
                    'Messages',
                  ),
                  _item(
                    SellerTab.profile,
                    Icons.person_outline,
                    Icons.person,
                    'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    SellerTab tab,
    IconData icon,
    IconData activeIcon,
    String label, {
    int badge = 0,
  }) {
    final selected = _tab == tab;
    final color = selected ? AppColors.coral : AppColors.gray;
    return Expanded(
      child: InkResponse(
        onTap: () => _select(tab),
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              backgroundColor: AppColors.coral,
              label: Text(badge > 9 ? '9+' : '$badge'),
              child: Icon(selected ? activeIcon : icon, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the account's role no longer includes selling.
class _NoSellerAccess extends StatelessWidget {
  const _NoSellerAccess();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(backgroundColor: AppColors.cream),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: AppColors.gray),
              SizedBox(height: 12),
              Text(
                'Seller Centre is not available for your role',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Request "Customer + Seller" from Profile → Change role.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
