import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../admin/admin_dashboard_screen.dart';
import '../customer/home_screen.dart';
import '../seller/seller_shell.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Returns the home screen matching [role].
///
/// * seller → Seller Centre ([SellerShell], bottom nav)
/// * admin → admin dashboard
/// * customer / both / unknown → customer home feed
Widget homeForRole(UserRole? role) {
  return switch (role) {
    UserRole.seller => const SellerShell(),
    UserRole.admin => const AdminDashboardScreen(),
    _ => const HomeScreen(),
  };
}

/// Where a signed-in user belongs: back into registration if their profile
/// is unfinished (first Google sign-in), otherwise their role home.
Widget destinationAfterAuth(AuthProvider auth) {
  if (auth.needsOnboarding) return const RegisterScreen.completeProfile();
  return homeForRole(auth.profile?.role);
}

/// Shown on Login when a signed-in user's profile could not be loaded.
const String profileLoadFailedNotice =
    "We couldn't load your account. Please log in again.";

/// Waits briefly for the profile doc after sign-in, then replaces the whole
/// stack with [destinationAfterAuth]. If the profile never arrives (missing
/// doc, permission-denied), signs out and returns to Login instead of
/// stranding the user in a half-signed-in Home.
///
/// [beforeNavigate] runs only when the profile loaded (e.g. a success
/// pop-up), right before navigating.
Future<void> goAfterAuth(
  BuildContext context, {
  Future<void> Function()? beforeNavigate,
}) async {
  final auth = context.read<AuthProvider>();
  final stopwatch = Stopwatch()..start();
  while (auth.profile == null &&
      stopwatch.elapsed < const Duration(seconds: 5)) {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;
  }
  if (!context.mounted) return;
  final blocked = auth.consumeBlockedReason();
  if (blocked != null) {
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(notice: blocked)),
      (_) => false,
    );
    return;
  }
  if (auth.profile == null) {
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(notice: profileLoadFailedNotice),
      ),
      (_) => false,
    );
    return;
  }
  if (beforeNavigate != null) {
    await beforeNavigate();
    if (!context.mounted) return;
  }
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => destinationAfterAuth(auth)),
    (_) => false,
  );
}

/// Signs out and returns to Login, clearing the navigation stack.
Future<void> signOutToLogin(BuildContext context) async {
  await context.read<AuthProvider>().signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
