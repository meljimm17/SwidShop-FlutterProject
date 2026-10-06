import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/rating_model.dart';
import '../../models/swap_offer_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import '../auth/role_home.dart';
import '../seller/seller_shell.dart';
import '../shared/rate_sheet.dart';
import 'activity_screen.dart';
import 'buyer_messages_screen.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'my_ratings_screen.dart';
import 'role_request_sheet.dart';
import 'trade_closet_screen.dart';

/// The user's own profile (Phase 3.11): real stats, tiles, edit, logout.
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
                _header(profile),
                const SizedBox(height: 16),
                _statsRow(profile),
                const SizedBox(height: 24),
                AppCardWrapper(
                  child: Column(
                    children: [
                      _row(Icons.mail_outline, 'Email', profile.email),
                      const Divider(),
                      _row(Icons.badge_outlined, 'Role', profile.role.label),
                      const Divider(),
                      _row(
                        Icons.location_on_outlined,
                        'Location',
                        [
                          profile.address.city,
                          profile.address.province,
                        ].where((e) => e.isNotEmpty).join(', '),
                      ),
                      const Divider(),
                      _row(
                        Icons.cake_outlined,
                        'Member since',
                        AppUtils.formatDate(profile.createdAt),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Sellers reach their shop from here too (not when this
                // Profile is already the Seller Centre's own tab).
                if (profile.role.canSell && !embedded)
                  _tile(
                    context,
                    Icons.storefront_outlined,
                    'Seller Centre',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SellerShell()),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: AppCardWrapper(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: RoleRequestTile(),
                  ),
                ),
                _tile(
                  context,
                  Icons.chat_bubble_outline,
                  'My Messages',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BuyerMessagesScreen(),
                    ),
                  ),
                ),
                _tile(
                  context,
                  Icons.history_outlined,
                  'Purchase History',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ActivityScreen(
                        initialTab: ActivityTab.purchases,
                      ),
                    ),
                  ),
                ),
                _tile(
                  context,
                  Icons.favorite_border,
                  'Favorites & Wishlist',
                  trailing:
                      '${profile.favorites.length} saved',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FavoritesScreen(),
                    ),
                  ),
                ),
                _tile(
                  context,
                  Icons.star_outline,
                  'My Ratings & Reviews',
                  trailingWidget: _pendingRatingsBadge(profile.uid),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MyRatingsScreen(),
                    ),
                  ),
                ),
                if (profile.role.canSell)
                  _tile(
                    context,
                    Icons.storefront_outlined,
                    'My Trade Closet',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TradeClosetScreen(),
                      ),
                    ),
                  ),
                _tile(
                  context,
                  Icons.edit_outlined,
                  'Edit Profile',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
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

  Widget _header(UserModel profile) {
    return Column(
      children: [
        CircleAvatar(
          radius: 46,
          backgroundColor: AppColors.coral,
          backgroundImage: profile.photoUrl.isNotEmpty
              ? NetworkImage(profile.photoUrl)
              : null,
          child: profile.photoUrl.isEmpty
              ? const Icon(Icons.person, size: 46, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          profile.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
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
      ],
    );
  }

  /// Real counts only: completed purchases, accepted swaps, review count.
  Widget _statsRow(UserModel profile) {
    final firestore = FirestoreService();
    return StreamBuilder<List<TransactionModel>>(
      stream: firestore.streamBuyerTransactions(profile.uid),
      builder: (context, txnSnap) {
        return StreamBuilder<List<SwapOfferModel>>(
          stream: firestore.streamOffersByUser(profile.uid),
          builder: (context, swapSnap) {
            return StreamBuilder<List<RatingModel>>(
              stream: firestore.streamRatingsForUser(profile.uid),
              builder: (context, ratingSnap) {
                final purchases = (txnSnap.data ?? const [])
                    .where((t) =>
                        t.status == TransactionStatus.completed)
                    .length;
                final swaps = (swapSnap.data ?? const [])
                    .where((o) => o.status == SwapOfferStatus.accepted)
                    .length;
                final reviews = (ratingSnap.data ?? const []).length;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('$purchases', 'Purchases'),
                    _stat('$swaps', 'Swaps'),
                    _stat(
                      profile.avgRating > 0
                          ? profile.avgRating.toStringAsFixed(1)
                          : '—',
                      'Rating',
                    ),
                    _stat('$reviews', 'Reviews'),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.gray),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label, {
    String? trailing,
    Widget? trailingWidget,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.teal, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (trailingWidget != null)
              trailingWidget
            else if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.gray,
                ),
              ),
            const Icon(Icons.chevron_right, color: AppColors.gray),
          ],
        ),
      ),
    );
  }

  /// "N pending" pill counting completed deals this user hasn't rated yet
  /// (mockup "2 Pending" — real data, computed once per build).
  Widget _pendingRatingsBadge(String uid) {
    return FutureBuilder<int>(
      future: _pendingRatingsCount(uid),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$n pending',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.amber,
            ),
          ),
        );
      },
    );
  }

  Future<int> _pendingRatingsCount(String uid) async {
    try {
      final firestore = FirestoreService();
      final lists = await Future.wait([
        firestore.streamBuyerTransactions(uid).first,
        firestore.streamSellerTransactions(uid).first,
      ]);
      var count = 0;
      for (final t in [...lists[0], ...lists[1]]) {
        if (t.status != TransactionStatus.completed) continue;
        final rated = await RateSheet.alreadyRated(t.transactionId, uid);
        if (!rated) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
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
