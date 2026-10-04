import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/transaction_model.dart';

/// One stat tile for the admin dashboard. Value is a precomputed string —
/// callers count from live streams (no fake numbers).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
          ),
        ],
      ),
    );
  }
}

/// Weekly deal counts stacked by listing type (last [weeks] weeks).
/// No chart package — plain columns, coral = Buy Now, amber = Bid,
/// teal = Swap. All values come from the given transactions.
class WeeklyStackedBars extends StatelessWidget {
  const WeeklyStackedBars({
    super.key,
    required this.transactions,
    this.weeks = 8,
    this.height = 150,
  });

  final List<TransactionModel> transactions;
  final int weeks;
  final double height;

  List<({DateTime week, int buyNow, int bid, int swap})> _buckets() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(monday.year, monday.month, monday.day);
    final buckets = List.generate(
      weeks,
      (i) => (
        week: start.subtract(Duration(days: 7 * (weeks - 1 - i))),
        buyNow: 0,
        bid: 0,
        swap: 0,
      ),
    );
    final counts = List.generate(weeks, (_) => [0, 0, 0]);
    for (final t in transactions) {
      final c = t.createdAt;
      if (c == null) continue;
      final day = DateTime(c.year, c.month, c.day);
      final diff = day.difference(buckets.first.week).inDays;
      if (diff < 0) continue;
      final i = diff ~/ 7;
      if (i >= weeks) continue;
      switch (t.type) {
        case ListingType.buyNow:
          counts[i][0]++;
        case ListingType.bid:
          counts[i][1]++;
        case ListingType.swap:
          counts[i][2]++;
      }
    }
    return List.generate(
      weeks,
      (i) => (
        week: buckets[i].week,
        buyNow: counts[i][0],
        bid: counts[i][1],
        swap: counts[i][2],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _buckets();
    var max = 1;
    for (final b in data) {
      final total = b.buyNow + b.bid + b.swap;
      if (total > max) max = total;
    }
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in data)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _seg(b.swap, max, AppColors.teal),
                        _seg(b.bid, max, AppColors.amber),
                        _seg(b.buyNow, max, AppColors.coral),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final b in data)
              Expanded(
                child: Text(
                  AppUtils.formatDate(b.week),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.gray),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(AppColors.coral, 'Buy Now'),
            SizedBox(width: 12),
            _Legend(AppColors.amber, 'Bidding'),
            SizedBox(width: 12),
            _Legend(AppColors.teal, 'Swap'),
          ],
        ),
      ],
    );
  }

  Widget _seg(int value, int max, Color color) {
    if (value <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: value,
      child: Container(
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(3),
          ),
        ),
        child: Center(
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

/// Proportional bars for listing-type distribution (live counts in).
class TypeDistributionBars extends StatelessWidget {
  const TypeDistributionBars({super.key, required this.listings});

  final List<ListingModel> listings;

  @override
  Widget build(BuildContext context) {
    final counts = <ListingType, int>{
      ListingType.buyNow: 0,
      ListingType.bid: 0,
      ListingType.swap: 0,
    };
    for (final l in listings) {
      counts[l.type] = (counts[l.type] ?? 0) + 1;
    }
    final total = listings.length;
    return Column(
      children: [
        _row('Buy Now', counts[ListingType.buyNow]!, total, AppColors.coral),
        const SizedBox(height: 8),
        _row('Bidding', counts[ListingType.bid]!, total, AppColors.amber),
        const SizedBox(height: 8),
        _row('Swap', counts[ListingType.swap]!, total, AppColors.teal),
      ],
    );
  }

  Widget _row(String label, int count, int total, Color color) {
    final frac = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: AppColors.line,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
