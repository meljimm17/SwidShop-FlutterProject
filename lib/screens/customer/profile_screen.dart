import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import '../auth/role_home.dart';

/// Displays the signed-in user's profile.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// True inside a bottom-nav tab (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(title: 'Profile', showBack: !embedded),
      body: profile == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (auth.isLoading)
                      const CircularProgressIndicator()
                    else
                      const Text(
                        "We couldn't load your profile.",
                        style: TextStyle(color: AppColors.gray),
                      ),
                    const SizedBox(height: 24),
                    // Always reachable, so a broken profile can't trap the
                    // user in a signed-in state.
                    PrimaryButton(
                      label: 'Sign out',
                      icon: Icons.logout,
                      onPressed: () => signOutToLogin(context),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: AppColors.coral,
                    backgroundImage: profile.photoUrl.isNotEmpty
                        ? NetworkImage(profile.photoUrl)
                        : null,
                    child: profile.photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 46, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StarRatingDisplay(
                        rating: profile.avgRating,
                        reviewCount: profile.completedTransactions,
                      ),
                      if (profile.trustedBadge) ...[
                        const SizedBox(width: 8),
                        const TrustedBadge(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppCardWrapper(
                  child: Column(
                    children: [
                      _row(Icons.mail_outline, 'Email', profile.email),
                      const Divider(),
                      _row(Icons.badge_outlined, 'Role', profile.role.value),
                      const Divider(),
                      _row(
                        Icons.location_on_outlined,
                        'Location',
                        [
                          profile.address.city,
                          profile.address.province,
                        ].where((e) => e.isNotEmpty).join(', '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Sign out',
                  icon: Icons.logout,
                  onPressed: () => signOutToLogin(context),
                ),
              ],
            ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gray, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.gray)),
          const Spacer(),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
