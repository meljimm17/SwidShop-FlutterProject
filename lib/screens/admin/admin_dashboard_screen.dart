import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import 'admin_charts.dart';
import 'admin_fees_screen.dart';
import 'admin_shell.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

/// Admin tab: greeting, live stat cards, deals per week, listing type
/// distribution, user growth and top sellers (Phase 4.1).
///
/// Every value is computed in [AdminStats] from the shared live streams.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final me = context.watch<AuthProvider>().profile;
    final now = DateTime.now();

    final roles = AdminStats.roleCounts(a.users);
    final active = a.listings
        .where((l) => l.status == ListingStatus.active)
        .toList();
    final types = AdminStats.typeCounts(active);
    final completed = a.transactions
        .where((t) => t.status == TransactionStatus.completed)
        .length;
    final mom = AdminStats.percentChange(
      AdminStats.completedInMonth(a.transactions, now: now),
      AdminStats.completedInMonth(a.transactions, monthOffset: -1, now: now),
    );
    final disputes = a.transactions
        .where((t) => t.status == TransactionStatus.disputed)
        .length;
    final growth = AdminStats.userGrowth(a.users, now: now);
    final growthPct = AdminStats.percentChange(
      growth.last.total,
      growth.first.total,
    );
    final top = AdminStats.topSellers(a.users);
    final first = (me?.firstName.isNotEmpty ?? false)
        ? me!.firstName
        : (me?.name.split(' ').first ?? '');

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            first.isEmpty ? 'Mabuhay!' : 'Mabuhay, $first',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_outlined,
                          size: 20,
                          color: AppColors.coralDeep,
                        ),
                      ],
                    ),
                    Text(
                      'SwidShop operations · ${AppUtils.formatDate(now)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              const SoftPill('Live Sync', color: AppColors.green, dot: true),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Total Users',
                    icon: Icons.people_alt_outlined,
                    iconColor: AppColors.ink,
                    value: compactCount(a.users.length),
                    onTap: () => AdminShell.goTo(context, AdminSection.users),
                    footer: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _MiniChip('${roles[UserRole.customer]} customers'),
                        _MiniChip('${roles[UserRole.both]} customer + seller'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Active Listings',
                    icon: Icons.sell_outlined,
                    iconColor: AppColors.coralDeep,
                    value: compactCount(active.length),
                    onTap: () =>
                        AdminShell.goTo(context, AdminSection.listings),
                    footer: Column(
                      children: [
                        for (final t in [
                          ListingType.buyNow,
                          ListingType.bid,
                          ListingType.swap,
                        ])
                          _DotRow(typeLabel(t), types[t]!, typeColor(t)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Settled Deals',
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.green,
                    value: compactCount(completed),
                    valueColor: AppColors.teal,
                    onTap: () => AdminShell.goTo(context, AdminSection.orders),
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppUtils.formatCurrency(AdminStats.settledVolume(a.transactions))} settled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.gray,
                          ),
                        ),
                        if (mom != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                mom >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 15,
                                color: mom >= 0
                                    ? AppColors.green
                                    : AppColors.red,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${mom >= 0 ? '+' : ''}$mom% MoM',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: mom >= 0
                                        ? AppColors.green
                                        : AppColors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Disputes',
                    icon: Icons.gavel_outlined,
                    iconColor: AppColors.red,
                    value: '$disputes Open',
                    valueColor: disputes > 0 ? AppColors.red : AppColors.ink,
                    onTap: () => AdminShell.goTo(context, AdminSection.reports),
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaction disputes awaiting review',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.gray,
                          ),
                        ),
                        if (disputes > 0) ...[
                          const SizedBox(height: 6),
                          const SoftPill('Needs Review', color: AppColors.red),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatCard(
            label: 'Pending Reports',
            icon: Icons.outlined_flag,
            iconColor: a.pendingQueueCount > 0 ? AppColors.red : AppColors.teal,
            value: '${a.pendingQueueCount}',
            valueColor: a.pendingQueueCount > 0 ? AppColors.red : AppColors.ink,
            onTap: () => AdminShell.goTo(context, AdminSection.reports),
            footer: Text(
              a.pendingQueueCount == 0
                  ? 'No reports awaiting review'
                  : 'Open user and listing reports · tap to review',
              style: const TextStyle(fontSize: 11.5, color: AppColors.gray),
            ),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Deals per Week',
            subtitle: 'New deals by listing type · last 6 weeks',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ChartLegend(
                  items: [
                    (AppColors.coral, 'Buy Now'),
                    (AppColors.amber, 'Bidding'),
                    (AppColors.teal, 'Swap'),
                  ],
                ),
                const SizedBox(height: 14),
                WeeklyGroupedBars(
                  data: AdminStats.weeklyDeals(a.transactions, now: now),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Listing Type Distribution',
            subtitle: 'Live active inventory',
            trailing: SoftPill('Total ${active.length}', color: AppColors.ink),
            child: TypeDonut(counts: types),
          ),
          const SizedBox(height: 12),
          _RevenueCard(admin: a),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'User Growth',
            subtitle: 'Registered users · last 6 months',
            trailing: growthPct == null
                ? null
                : SoftPill(
                    '${growthPct >= 0 ? '+' : ''}$growthPct%',
                    color: growthPct >= 0 ? AppColors.green : AppColors.red,
                    icon: growthPct >= 0
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
            child: GrowthLine(data: growth),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top / Trusted Sellers',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Trusted first, then rating and completed deals',
                      style: TextStyle(fontSize: 12, color: AppColors.gray),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => AdminShell.goTo(context, AdminSection.users),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.coralDeep,
                ),
                child: const Text('View All ›'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const AdminCard(
              child: Text(
                'No sellers with completed deals yet.',
                style: TextStyle(color: AppColors.gray),
              ),
            )
          else
            SizedBox(
              height: 238,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: top.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _SellerCard(user: top[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.footer,
    this.valueColor = AppColors.ink,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final Widget footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          footer,
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.mist,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
    ),
  );
}

class _DotRow extends StatelessWidget {
  const _DotRow(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Demo revenue section (all figures demo-mode, labeled as such).
class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.admin});

  final AdminProvider admin;

  @override
  Widget build(BuildContext context) {
    final payments = admin.payments;
    final byStream = RevenueStats.byStream(payments, admin.partnerAds);
    final total = RevenueStats.total(byStream);
    final fees = RevenueStats.fees(admin.transactions);
    final plans = RevenueStats.paidPlans(admin.users);
    final boosted = RevenueStats.activeBoosts(admin.users);
    final weekly = RevenueStats.weekly(payments);

    return _ChartCard(
      title: 'Revenue',
      subtitle: 'Fees, plans, boosts, featured, photo packs & ads',
      trailing: TextButton(
        onPressed: () => openAdminFees(context),
        style: TextButton.styleFrom(foregroundColor: AppColors.coralDeep),
        child: const Text('Fees ›'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppUtils.formatCurrency(total),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const Text(
            'Total revenue',
            style: TextStyle(fontSize: 12, color: AppColors.gray),
          ),
          const SizedBox(height: 10),
          for (final k in RevenueStats.streams)
            _streamRow(RevenueStats.labels[k] ?? k, byStream[k] ?? 0, total),
          const SizedBox(height: 14),
          const Text(
            'Weekly revenue (payments)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          WeeklyRevenueBars(data: weekly),
          const Divider(height: 24),
          _kv('Fees Collected', AppUtils.formatCurrency(fees.collected)),
          _kv('Fees Outstanding', AppUtils.formatCurrency(fees.outstanding)),
          if (fees.overdue > 0)
            _kv('  of which overdue', AppUtils.formatCurrency(fees.overdue)),
          _kv('Active boosts', '$boosted shop${boosted == 1 ? '' : 's'}'),
          _kv('Active Plus / Pro sellers', '${plans.plus} / ${plans.pro}'),
        ],
      ),
    );
  }

  Widget _streamRow(String label, double value, double total) {
    final frac = total <= 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor: AppColors.line,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.teal),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              AppUtils.formatCurrency(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
            ),
          ),
          Text(
            v,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final city = user.address.city;
    return SizedBox(
      width: 200,
      child: AdminCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        onTap: () => openAdminUserDetail(context, user.uid),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminAvatar(user: user, size: 58, showStatus: false),
                const SizedBox(width: 6),
                if (user.trustedBadge)
                  const Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SoftPill(
                        'Trusted',
                        color: AppColors.teal,
                        icon: Icons.verified_outlined,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              user.name.isEmpty ? user.email : user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '${user.avgRating.toStringAsFixed(1)} · '
                    '${user.completedTransactions} deal${user.completedTransactions == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              city.isEmpty
                  ? roleLabel(user.role)
                  : '${roleLabel(user.role)} · $city',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.gray),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => openAdminUserDetail(context, user.uid),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coralDeep,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('View Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
