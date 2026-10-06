import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/top_app_bar.dart';
import 'boost_sheet.dart';
import 'fee_payments.dart';
import 'plans_screen.dart';

/// Seller Centre hub linking every demo purchase (Step 1 requirement).
class GrowMyShopScreen extends StatelessWidget {
  const GrowMyShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final plan = profile?.effectivePlan ?? 'free';
    final boosted = profile?.isBoosted ?? false;
    final seller = context.watch<SellerProvider>()..start();
    final unpaid = unpaidFees(seller.transactions);
    var owed = 0.0;
    for (final t in unpaid) {
      owed += t.feeAmount;
    }
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Grow My Shop'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Paid boosts live here. Posting listings is always free; '
            'swaps never carry commission.',
            style: TextStyle(color: AppColors.gray, height: 1.45),
          ),
          const SizedBox(height: 16),
          _link(
            context,
            Icons.workspace_premium_outlined,
            'Plans',
            plan == 'free'
                ? 'Free · upgrade to Plus or Pro'
                : '${plan[0].toUpperCase()}${plan.substring(1)} plan active',
            () => openPlans(context),
          ),
          _link(
            context,
            Icons.rocket_launch_outlined,
            'Boost My Shop',
            boosted
                ? 'Boosted until ${AppUtils.formatDate(profile?.boostedUntil)} — extend it'
                : '${AppConstants.boostDurations.join(', ')} days in the Sponsored carousel',
            () => showBoostSheet(context),
          ),
          _link(
            context,
            Icons.photo_library_outlined,
            'Photo Pack',
            plan == 'free'
                ? 'One-time unlock: ${AppConstants.photoLimits['pack']} photos on a listing'
                : 'Included in your plan',
            () => _photoPackInfo(context),
          ),
          _link(
            context,
            Icons.star_outline,
            'Feature a Listing',
            '${AppConstants.featuredDays}-day Sponsored slot + Featured tag · ${AppUtils.formatCurrency(AppConstants.featuredPrice)}',
            () => _pickListingToFeature(context, seller.listings),
          ),
          _link(
            context,
            Icons.receipt_long_outlined,
            'Platform Fees',
            unpaid.isEmpty
                ? 'Nothing owed — all fees paid'
                : '${AppUtils.formatCurrency(owed)} unpaid · tap to pay',
            unpaid.isEmpty ? () {} : () => payAllFees(context, unpaid),
          ),
        ],
      ),
    );
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCardWrapper(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.coral, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
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

  void _photoPackInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Photo Pack'),
        content: Text(
          'Free sellers get ${AppConstants.photoLimits['free']} photos per '
          'listing. Buy the one-time Photo Pack '
          '(${AppUtils.formatCurrency(AppConstants.photoPackPrice)}) when a '
          'listing asks for one more photo — it unlocks '
          '${AppConstants.photoLimits['pack']} photos on that listing. Plus '
          'and Pro include it on everything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Pick one of your active listings, then pay for its Featured slot.
  Future<void> _pickListingToFeature(
    BuildContext context,
    List<ListingModel> listings,
  ) async {
    final active = listings
        .where((l) => l.status == ListingStatus.active)
        .toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post an active listing to feature it.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<ListingModel>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Which listing should be featured?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final l in active)
                ListTile(
                  title: Text(
                    l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    l.isFeatured
                        ? 'Featured until ${AppUtils.formatDate(l.featuredUntil)} — extend'
                        : 'Not featured',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(sheet).pop(l),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await featureListing(
      context,
      listingId: picked.listingId,
      title: picked.title,
    );
  }
}

/// Re-runs the client-side scheduler for tests/previews.
Future<void> refreshSellerPerks(String uid) =>
    FirestoreService().runSellerMaintenance(uid);
