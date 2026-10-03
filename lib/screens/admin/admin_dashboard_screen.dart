import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import '../auth/role_home.dart';

/// Admin dashboard: moderation & platform overview.
///
/// This is a scaffold — wire the report queue and trust-badge controls to the
/// `reports` collection and the `trust-badge` Cloud Function.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(
        title: 'Admin',
        showBack: false,
        onLogout: () => signOutToLogin(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          AppCardWrapper(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined, color: AppColors.red),
              title: Text('Reports queue'),
              subtitle: Text('pending = 0'),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
          SizedBox(height: 12),
          AppCardWrapper(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.people_outline, color: AppColors.teal),
              title: Text('Users'),
              subtitle: Text('Manage roles & trust badges'),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
          SizedBox(height: 12),
          AppCardWrapper(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.gavel_outlined, color: AppColors.amber),
              title: Text('Auctions'),
              subtitle: Text('Close expired auctions (auction-close fn)'),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }
}
