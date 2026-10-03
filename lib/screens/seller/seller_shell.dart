import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/seller_provider.dart';
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
  }

  void _select(SellerTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
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
