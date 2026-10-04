import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import '../auth/role_home.dart';
import 'admin_categories_screen.dart';
import 'admin_charts.dart';
import 'admin_gate.dart';
import 'admin_listings_screen.dart';
import 'admin_ratings_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_transactions_screen.dart';
import 'admin_users_screen.dart';

/// Admin entry point: drawer nav, live stat cards and charts (Phase 4.1).
///
/// Everything here streams — cards and charts refresh on snapshot updates.
/// Pull-to-refresh re-runs the build immediately.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firestore = FirestoreService();

  Future<void> _refresh() async {
    setState(() {});
  }

  void _go(Widget screen) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminGate(child: screen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: TopAppBar(
          title: 'Admin Dashboard',
          showBack: false,
          onLogout: () => signOutToLogin(context),
        ),
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const DrawerHeader(
                  decoration: BoxDecoration(color: AppColors.cream),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'SwidShop Admin',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.coral,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Moderation & overview',
                        style: TextStyle(color: AppColors.gray),
                      ),
                    ],
                  ),
                ),
                _drawerItem(Icons.dashboard_outlined, 'Dashboard', null),
                _drawerItem(Icons.people_outline, 'Users',
                    const AdminUsersScreen()),
                _drawerItem(Icons.storefront_outlined, 'Listings',
                    const AdminListingsScreen()),
                _drawerItem(Icons.receipt_long_outlined, 'Transactions',
                    const AdminTransactionsScreen()),
                _drawerItem(Icons.flag_outlined, 'Reports',
                    const AdminReportsScreen()),
                _drawerItem(Icons.star_outline, 'Ratings & Reviews',
                    const AdminRatingsScreen()),
                _drawerItem(Icons.category_outlined, 'Categories',
                    const AdminCategoriesScreen()),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.logout, color: AppColors.ink),
                  title: const Text('Log Out'),
                  onTap: () => signOutToLogin(context),
                ),
              ],
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: StreamBuilder<List<UserModel>>(
            stream: _firestore.streamAllUsers(),
            builder: (context, userSnap) {
              return StreamBuilder<List<ListingModel>>(
                stream: _firestore.streamAllListings(),
                builder: (context, listingSnap) {
                  return StreamBuilder<List<TransactionModel>>(
                    stream: _firestore.streamAllTransactions(),
                    builder: (context, txnSnap) {
                      return StreamBuilder<List<ReportModel>>(
                        stream: _firestore.streamReportsByStatus(
                          ReportStatus.pending,
                        ),
                        builder: (context, reportSnap) {
                          if (!userSnap.hasData ||
                              !listingSnap.hasData ||
                              !txnSnap.hasData ||
                              !reportSnap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _body(
                            users: userSnap.data!,
                            listings: listingSnap.data!,
                            txns: txnSnap.data!,
                            pendingReports:
                                reportSnap.data!.length,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, Widget? screen) {
    return ListTile(
      leading: Icon(icon, color: AppColors.teal),
      title: Text(label),
      trailing: screen == null
          ? const Icon(Icons.check, color: AppColors.teal, size: 18)
          : const Icon(Icons.chevron_right, color: AppColors.gray),
      onTap: screen == null
          ? () => Navigator.of(context).pop()
          : () => _go(screen),
    );
  }

  Widget _body({
    required List<UserModel> users,
    required List<ListingModel> listings,
    required List<TransactionModel> txns,
    required int pendingReports,
  }) {
    final active =
        listings.where((l) => l.status == ListingStatus.active).length;
    final settled = txns
        .where((t) => t.status == TransactionStatus.completed)
        .length;
    final disputes = txns
        .where((t) => t.status == TransactionStatus.disputed)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            StatCard(
              label: 'Total Users',
              value: '${users.length}',
              icon: Icons.people_outline,
              color: AppColors.teal,
            ),
            StatCard(
              label: 'Active Listings',
              value: '$active',
              icon: Icons.storefront_outlined,
              color: AppColors.coral,
            ),
            StatCard(
              label: 'Settled Orders',
              value: '$settled',
              icon: Icons.check_circle_outline,
              color: AppColors.green,
            ),
            StatCard(
              label: 'Open Disputes',
              value: '$disputes',
              icon: Icons.warning_amber_outlined,
              color: AppColors.red,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Deals per Week',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (pendingReports > 0)
                    GestureDetector(
                      onTap: () => _go(const AdminReportsScreen()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$pendingReports pending',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              WeeklyStackedBars(transactions: txns),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Listing Type Distribution',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TypeDistributionBars(listings: listings),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Updated ${AppUtils.formatDateTime(DateTime.now())}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.gray),
          ),
        ),
      ],
    );
  }
}
