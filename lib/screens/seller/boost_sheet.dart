import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../shared/demo_gcash_screen.dart';

/// Bottom sheet: 3/7/14-day shop boost (Step 4). Extends an active boost.
Future<void> showBoostSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _BoostSheet(),
  );
}

class _BoostSheet extends StatefulWidget {
  const _BoostSheet();

  @override
  State<_BoostSheet> createState() => _BoostSheetState();
}

class _BoostSheetState extends State<_BoostSheet> {
  int _days = 7;
  bool _busy = false;

  Future<void> _buy() async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty || _busy) return;
    final days = _days;
    final price = AppConstants.boostPrices[days] ?? 0;
    DateTime? until;
    setState(() => _busy = true);
    final ref = await runDemoPayment(
      context,
      itemLabel: 'Shop boost · $days days',
      amount: price,
      apply: (ref) async {
        until = await FirestoreService().purchaseBoost(
          uid: uid,
          days: days,
          referenceNo: ref,
        );
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref != null) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Shop boosted until ${AppUtils.formatDate(until)}!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final until = context.select<AuthProvider, DateTime?>(
      (a) => a.profile?.boostedUntil,
    );
    final active = until != null && until.isAfter(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Boost My Shop',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              active
                  ? 'Boosted until ${AppUtils.formatDateTime(until)} — buying more extends it.'
                  : 'Your active listings join the Sponsored carousel.',
              style: const TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final d in AppConstants.boostDurations)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '$d days\n₱${(AppConstants.boostPrices[d] ?? 0).toStringAsFixed(0)}',
                        ),
                        selected: _days == d,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _days = d),
                        selectedColor: AppColors.coral,
                        labelStyle: TextStyle(
                          color: _days == d ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: AppColors.cream,
                        side: BorderSide(
                          color: _days == d
                              ? AppColors.coral
                              : AppColors.line,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _buy,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Boost for ${AppUtils.formatCurrency(AppConstants.boostPrices[_days])}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Featured slot for one listing (Step 5): Sponsored carousel + Featured
/// tag for [AppConstants.featuredDays] days, extending an active one.
Future<bool> featureListing(
  BuildContext context, {
  required String listingId,
  required String title,
}) async {
  final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
  if (uid.isEmpty) return false;
  DateTime? until;
  final ref = await runDemoPayment(
    context,
    itemLabel: 'Featured listing · ${AppConstants.featuredDays} days',
    amount: AppConstants.featuredPrice,
    apply: (ref) async {
      until = await FirestoreService().purchaseFeatured(
        uid: uid,
        listingId: listingId,
        referenceNo: ref,
      );
    },
  );
  if (ref != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Featured until ${AppUtils.formatDate(until)}!'),
      ),
    );
  }
  return ref != null;
}

/// One-time Photo Pack (Step 3): 8 photos on [listingId]. Works before the
/// listing is saved — `createListing` then stamps the limit.
Future<bool> buyPhotoPack(
  BuildContext context, {
  required String listingId,
  required String title,
}) async {
  final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
  if (uid.isEmpty) return false;
  final ref = await runDemoPayment(
    context,
    itemLabel: 'Photo Pack · $title',
    amount: AppConstants.photoPackPrice,
    apply: (ref) => FirestoreService().purchasePhotoPack(
      uid: uid,
      listingId: listingId,
      title: title,
      referenceNo: ref,
    ),
  );
  return ref != null;
}
