import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../auth/role_home.dart';
import 'admin_categories_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_fees_screen.dart';
import 'admin_ads_screen.dart';
import 'admin_gate.dart';
import 'admin_listings_screen.dart';
import 'admin_ratings_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_role_requests_screen.dart';
import 'admin_transactions_screen.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

/// Admin sections. The first five are on the bottom bar; Ratings and
/// Categories open from the ☰ drawer (bottom bar stays visible).
enum AdminSection {
  dashboard('Dashboard'),
  users('Users'),
  listings('Listings'),
  orders('Transactions'),
  reports('Reports'),
  ratings('Ratings & Reviews'),
  categories('Categories'),
  roleRequests('Role Requests');

  const AdminSection(this.title);

  final String title;
}

/// Admin side of the app: top bar (☰ · title · bell · avatar), drawer and
/// bottom navigation Admin · Users · Listings · Orders · Reports.
///
/// Owns one [AdminProvider] so every tab shares the same live streams.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    this.initial = AdminSection.dashboard,
    this.firestoreService,
  });

  final AdminSection initial;

  /// Test hook; production uses the real service.
  final FirestoreService? firestoreService;

  /// Switches the enclosing shell's section (no-op outside a shell).
  static void goTo(BuildContext context, AdminSection section) =>
      context.findAncestorStateOfType<_AdminFrameState>()?._select(section);

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: ChangeNotifierProvider(
        create: (_) => AdminProvider(firestoreService: firestoreService),
        child: _AdminFrame(initial: initial),
      ),
    );
  }
}

class _AdminFrame extends StatefulWidget {
  const _AdminFrame({required this.initial});

  final AdminSection initial;

  @override
  State<_AdminFrame> createState() => _AdminFrameState();
}

class _AdminFrameState extends State<_AdminFrame> {
  late AdminSection _section = widget.initial;
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Sections built so far (lazy IndexedStack: unvisited tabs cost nothing).
  late final Set<AdminSection> _built = {widget.initial};

  void _select(AdminSection s) {
    if (s == _section) return;
    setState(() {
      _section = s;
      _built.add(s);
    });
  }

  Widget _page(AdminSection s) => switch (s) {
    AdminSection.dashboard => const AdminDashboardScreen(),
    AdminSection.users => const AdminUsersScreen(),
    AdminSection.listings => const AdminListingsScreen(),
    AdminSection.orders => const AdminTransactionsScreen(),
    AdminSection.reports => const AdminReportsScreen(),
    AdminSection.ratings => const AdminRatingsScreen(),
    AdminSection.categories => const AdminCategoriesScreen(),
    AdminSection.roleRequests => const AdminRoleRequestsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final me = context.watch<AuthProvider>().profile;
    final queue = admin.pendingQueueCount;

    return PopScope(
      canPop: _section == AdminSection.dashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(AdminSection.dashboard);
      },
      child: Scaffold(
        key: _scaffold,
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, color: AppColors.ink),
            onPressed: () => _scaffold.currentState?.openDrawer(),
          ),
          title: Text(
            _section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Report queue',
              onPressed: () => _select(AdminSection.reports),
              icon: Badge(
                isLabelVisible: queue > 0,
                backgroundColor: AppColors.red,
                label: Text(queue > 9 ? '9+' : '$queue'),
                child: const Icon(
                  Icons.notifications_none,
                  color: AppColors.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: PopupMenuButton<String>(
                tooltip: 'Account',
                position: PopupMenuPosition.under,
                color: AppColors.surface,
                onSelected: (v) {
                  if (v == 'logout') signOutToLogin(context);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      me?.name.isNotEmpty == true ? me!.name : 'Admin',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: AppColors.ink),
                        SizedBox(width: 10),
                        Text('Log out'),
                      ],
                    ),
                  ),
                ],
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.coralDeep,
                  child: const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        ),
        drawer: _drawer(admin),
        body: admin.isLoading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _section.index,
                children: [
                  for (final s in AdminSection.values)
                    _built.contains(s) ? _page(s) : const SizedBox.shrink(),
                ],
              ),
      ),
    );
  }

  Widget _drawer(AdminProvider admin) {
    Widget item(AdminSection s, IconData icon, {int count = 0}) {
      final selected = _section == s;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: ListTile(
          selected: selected,
          selectedTileColor: AppColors.coral.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Icon(
            icon,
            color: selected ? AppColors.coralDeep : AppColors.ink,
          ),
          title: Text(
            s.title,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.coralDeep : AppColors.ink,
            ),
          ),
          trailing: count > 0 ? SoftPill('$count', color: AppColors.red) : null,
          onTap: () {
            Navigator.of(context).pop();
            _select(s);
          },
        ),
      );
    }

    return Drawer(
      backgroundColor: AppColors.paper,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/swidshop_mark.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.storefront,
                      color: AppColors.coral,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SwidShop Admin',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'Moderation & overview',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            item(AdminSection.dashboard, Icons.space_dashboard_outlined),
            item(AdminSection.users, Icons.people_outline),
            item(AdminSection.listings, Icons.inventory_2_outlined),
            item(AdminSection.orders, Icons.receipt_long_outlined),
            item(
              AdminSection.reports,
              Icons.outlined_flag,
              count: admin.pendingQueueCount,
            ),
            item(
              AdminSection.ratings,
              Icons.star_outline,
              count: admin.pendingRatingFlags,
            ),
            item(AdminSection.categories, Icons.category_outlined),
            item(
              AdminSection.roleRequests,
              Icons.manage_accounts_outlined,
              count: admin.pendingRoleRequests,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(
                  Icons.payments_outlined,
                  color: AppColors.ink,
                ),
                title: const Text(
                  'Fees',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  openAdminFees(context);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(
                  Icons.campaign_outlined,
                  color: AppColors.ink,
                ),
                title: const Text(
                  'Manage Ads',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  openAdminAds(context);
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Divider(color: AppColors.line),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.logout, color: AppColors.red),
                title: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => signOutToLogin(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
