import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/seller_provider.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/monthly_bars.dart';

/// Seller analytics from live data: sell-through, average sale, monthly
/// settled totals and a breakdown by listing type.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SellerProvider>().start();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SellerProvider>();
    final completed = s.completedSales;
    final counted = s.listings
        .where((l) => l.status != ListingStatus.removed)
        .length;
    final sold = s.listings.where((l) => l.status == ListingStatus.sold).length;
    final sellThrough = SellerStats.sellThrough(s.listings);
    final paid = completed.where((t) => t.amount > 0).toList();
    final avgSale = paid.isEmpty
        ? null
        : paid.fold<double>(0, (a, t) => a + t.amount) / paid.length;
    final monthly = SellerStats.monthlySettled(s.transactions);
    final sixMonthTotal = monthly.fold<double>(0, (a, m) => a + m.total);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        title: const Text('Analytics'),
      ),
      body: s.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _hero(sellThrough, sold, counted),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        label: 'Average sale',
                        value: avgSale == null
                            ? '—'
                            : AppUtils.formatCurrency(avgSale),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        label: 'Completed deals',
                        value: '${completed.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        label: 'Active now',
                        value: '${s.activeListings.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                OutlineCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Settled per month',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Last 6 months · ${AppUtils.formatCurrency(sixMonthTotal)}'
                        ' total · tap a bar',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.gray,
                        ),
                      ),
                      const SizedBox(height: 14),
                      MonthlyBars(data: monthly, height: 140),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlineCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Completed by type',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final (type, label, color) in [
                        (ListingType.buyNow, 'Buy Now', AppColors.coral),
                        (ListingType.bid, 'Auction wins', AppColors.amber),
                        (ListingType.swap, 'Swaps', AppColors.teal),
                      ])
                        _typeRow(completed, type, label, color),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hero(double? sellThrough, int sold, int counted) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sell-through rate',
                  style: TextStyle(fontSize: 13, color: AppColors.gray),
                ),
                const SizedBox(height: 4),
                Text(
                  sellThrough == null ? '—' : '${(sellThrough * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                Text(
                  counted == 0
                      ? 'Post a listing to start tracking.'
                      : '$sold of $counted listing${counted == 1 ? '' : 's'} '
                            'ended in a deal',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: sellThrough ?? 0,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: AppColors.green,
              backgroundColor: AppColors.mist,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeRow(
    List<TransactionModel> completed,
    ListingType type,
    String label,
    Color color,
  ) {
    final rows = completed.where((t) => t.type == type).toList();
    final share = completed.isEmpty ? 0.0 : rows.length / completed.length;
    final total = rows.fold<double>(0, (a, t) => a + t.amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                type == ListingType.swap
                    ? '${rows.length} deal${rows.length == 1 ? '' : 's'}'
                    : '${rows.length} · ${AppUtils.formatCurrency(total)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 8,
              color: color,
              backgroundColor: AppColors.mist,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.gray),
          ),
        ],
      ),
    );
  }
}
