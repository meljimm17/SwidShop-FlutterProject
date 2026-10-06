import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';
import '../shared/demo_gcash_screen.dart';

String _planName(String plan) =>
    plan.isEmpty ? plan : '${plan[0].toUpperCase()}${plan.substring(1)}';

/// Opens the Plans page.
Future<void> openPlans(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlansScreen()),
    );

/// Locked-feature prompt: lock icon, why, and a "See Plans" button.
Future<void> showUpgradePrompt(
  BuildContext context, {
  required String feature,
  String plan = 'Pro',
}) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40, color: AppColors.coral),
            const SizedBox(height: 10),
            Text(
              '$feature is a $plan feature',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Upgrade to $plan to unlock it.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'See Plans',
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
  if (go == true && context.mounted) await openPlans(context);
}

/// Small trailing lock for locked tiles/rows.
class LockIcon extends StatelessWidget {
  const LockIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.lock_outline, size: size, color: AppColors.gray);
}

/// Seller plans: Free / Plus / Pro (Step 3, demo monthly subscriptions).
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _busy = false;

  Future<void> _subscribe(UserModel? profile, String plan) async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid.isEmpty || _busy) return;
    final current = profile?.effectivePlan ?? 'free';
    // Switching away from a running paid plan ends it today.
    if (current != 'free' && current != plan) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Switch to ${_planName(plan)}?'),
          content: Text(
            'Your ${_planName(current)} plan'
            '${profile?.planUntil == null ? '' : ' (until ${AppUtils.formatDate(profile!.planUntil)})'}'
            ' ends today and ${_planName(plan)} starts for '
            '${AppConstants.planDays} days. Unused days are not carried over.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Keep current'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final price = AppConstants.planPrices[plan] ?? 0;
    DateTime? until;
    setState(() => _busy = true);
    final ref = await runDemoPayment(
      context,
      itemLabel: '${_planName(plan)} plan · ${AppConstants.planDays} days',
      amount: price,
      apply: (ref) async {
        until = await FirestoreService().purchasePlan(
          uid: uid,
          plan: plan,
          referenceNo: ref,
        );
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_planName(plan)} active until ${AppUtils.formatDate(until)}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final current = profile?.effectivePlan ?? 'free';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Plans'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Posting is always free and swaps never carry commission. Plans '
            'are monthly and cut the fee on Bidding + Buy Now sales.',
            style: TextStyle(color: AppColors.gray, height: 1.45),
          ),
          const SizedBox(height: 14),
          _ComparisonTable(current: current),
          const SizedBox(height: 16),
          for (final plan in const ['plus', 'pro']) ...[
            _planCard(profile, plan, current),
            const SizedBox(height: 12),
          ],
          const Center(
            child: Text(
              'Plans renew manually — nothing is charged automatically.',
              style: TextStyle(fontSize: 11, color: AppColors.gray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(UserModel? profile, String plan, String current) {
    final isCurrent = current == plan;
    final price = AppConstants.planPrices[plan] ?? 0;
    final rate = (Fees.rateFor(plan) * 100).toStringAsFixed(0);
    return AppCardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _planName(plan),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isCurrent) const _Pill('Current', AppColors.coral),
            ],
          ),
          Text(
            '${AppUtils.formatCurrency(price)} / ${AppConstants.planDays} days · $rate% commission',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.coral,
            ),
          ),
          if (isCurrent && profile?.planUntil != null) ...[
            const SizedBox(height: 4),
            Text(
              'Active until ${AppUtils.formatDate(profile!.planUntil)} — '
              'renewing adds ${AppConstants.planDays} days.',
              style: const TextStyle(color: AppColors.gray, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: isCurrent ? 'Renew' : 'Subscribe',
            loading: _busy,
            onPressed: _busy ? null : () => _subscribe(profile, plan),
          ),
        ],
      ),
    );
  }
}

/// Free / Plus / Pro side by side (values straight from AppConstants).
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    String pct(String p) => '${(Fees.rateFor(p) * 100).toStringAsFixed(0)}%';
    String photos(String p) => '${AppConstants.photoLimits[p]}';
    const yes = '✓';
    const no = '—';
    final rows = <(String, String, String, String)>[
      (
        'Price / month',
        '₱0',
        AppUtils.formatCurrency(AppConstants.planPrices['plus']),
        AppUtils.formatCurrency(AppConstants.planPrices['pro']),
      ),
      ('Commission (Bid, Buy Now)', pct('free'), pct('plus'), pct('pro')),
      ('Swap commission', '0%', '0%', '0%'),
      ('Photos per listing', photos('free'), photos('plus'), photos('pro')),
      (
        'Photo Pack (8 photos)',
        AppUtils.formatCurrency(AppConstants.photoPackPrice),
        'Included',
        'Included',
      ),
      ('Verified badge', no, yes, yes),
      ('Plan badge', no, 'Plus', 'Pro'),
      ('Sales Analytics', no, no, yes),
      (
        'Longest auction',
        '${AppConstants.maxAuctionDays} days',
        '${AppConstants.maxAuctionDays} days',
        '${AppConstants.maxProAuctionDays} days',
      ),
      ('Buy It Now on auctions', no, no, yes),
      ('Bump Listing (daily)', no, no, yes),
      ('Highlighted listing', no, no, yes),
    ];
    const plans = ['free', 'plus', 'pro'];
    TextStyle head(String p) => TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: p == current ? AppColors.coral : AppColors.ink,
        );
    Widget cell(String text, {TextStyle? style, bool first = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Text(
            text,
            textAlign: first ? TextAlign.start : TextAlign.center,
            style: style ?? const TextStyle(fontSize: 12),
          ),
        );
    return AppCardWrapper(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(
          horizontalInside: BorderSide(color: AppColors.line),
        ),
        children: [
          TableRow(
            children: [
              cell('', first: true),
              for (final p in plans) cell(_planName(p), style: head(p)),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [
                cell(
                  r.$1,
                  first: true,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                cell(r.$2),
                cell(r.$3),
                cell(r.$4),
              ],
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
