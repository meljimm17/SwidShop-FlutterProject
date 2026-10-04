import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';
import '../auth/role_home.dart';

/// True only for signed-in admins. Every admin screen gates on this —
/// a non-admin can never reach an admin route, even by deep push.
bool isAdmin(AuthProvider auth) =>
    auth.isLoggedIn && auth.profile?.role == UserRole.admin;

/// Wraps admin screens: non-admins get a dead-end notice, never content.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (isAdmin(auth)) return child;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 56,
                color: AppColors.gray,
              ),
              const SizedBox(height: 16),
              const Text(
                'Admins only.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'This area requires an admin account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Sign out',
                icon: Icons.logout,
                onPressed: () => signOutToLogin(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
