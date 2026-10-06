import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import 'admin_widgets.dart';

/// Admin dashboard charts. No chart package: plain widgets + painters.
/// Type colours are fixed per entity (coral Buy Now, amber Bidding, teal
/// Swap) and never re-assigned by rank. Values always come from live data.

/// Legend chip: coloured square + label (identity is never colour-alone).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ],
          ),
      ],
    );
  }
}

/// Deals per week, three bars per week (Buy Now · Bidding · Swap).
/// Tap a week to read its exact counts.
class WeeklyGroupedBars extends StatefulWidget {
  const WeeklyGroupedBars({super.key, required this.data, this.height = 170});

  final List<({DateTime week, int buyNow, int bid, int swap})> data;
  final double height;

  @override
  State<WeeklyGroupedBars> createState() => _WeeklyGroupedBarsState();
}

class _WeeklyGroupedBarsState extends State<WeeklyGroupedBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return SizedBox(height: widget.height);
    var max = 0;
    for (final d in data) {
      max = math.max(max, math.max(d.buyNow, math.max(d.bid, d.swap)));
    }
    final top = _niceCeil(max);
    final sel = _selected ?? data.length - 1;
    final fmt = DateFormat('MMM d');
    final s = data[sel];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: 'Week of ${fmt.format(s.week)}  ',
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
            children: [
              TextSpan(
                text: '${s.buyNow} buy now · ${s.bid} auction · ${s.swap} swap',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Y axis: 0, mid, top (recessive).
              SizedBox(
                width: 26,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final v in [top, top ~/ 2, 0])
                      Text(
                        '$v',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.gray,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          3,
                          (i) => Container(
                            height: 1,
                            color: i == 2 ? AppColors.line : AppColors.mist,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < data.length; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _selected = i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (final (v, c) in [
                                      (data[i].buyNow, AppColors.coral),
                                      (data[i].bid, AppColors.amber),
                                      (data[i].swap, AppColors.teal),
                                    ])
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 1,
                                          ),
                                          child: _bar(v, top, c, dim: i != sel),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 26),
            for (var i = 0; i < data.length; i++)
              Expanded(
                child: Text(
                  fmt.format(data[i].week),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    color: i == sel ? AppColors.ink : AppColors.gray,
                    fontWeight: i == sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bar(int v, int top, Color color, {required bool dim}) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = v <= 0 ? 2.0 : math.max(4.0, v / top * c.maxHeight);
        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: h,
            decoration: BoxDecoration(
              color: v <= 0
                  ? AppColors.line
                  : color.withValues(alpha: dim ? 0.55 : 1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Rounds up to a readable axis maximum (at least 4).
int _niceCeil(int v) {
  if (v <= 4) return 4;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toInt();
  for (final m in [1, 2, 2.5, 5, 10]) {
    final c = (m * mag).ceil();
    if (c >= v) return c.isEven ? c : c + 1;
  }
  return v;
}

/// Donut of active listings by type with the total in the centre and a
/// share tile per type underneath.
class TypeDonut extends StatelessWidget {
  const TypeDonut({super.key, required this.counts});

  final Map<ListingType, int> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    const order = [ListingType.buyNow, ListingType.bid, ListingType.swap];
    return Column(
      children: [
        SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [for (final t in order) counts[t] ?? 0],
              colors: [for (final t in order) typeColor(t)],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _compact(total),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const Text(
                    'Active listings',
                    style: TextStyle(fontSize: 11.5, color: AppColors.gray),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final t in order) ...[
              if (t != order.first) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: typeColor(t),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              typeLabel(t),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        total == 0
                            ? '—'
                            : '${((counts[t] ?? 0) / total * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${counts[t] ?? 0} item${counts[t] == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        paint..color = AppColors.mist,
      );
      return;
    }
    final nonZero = values.where((v) => v > 0).length;
    // 2px surface gap between segments (only when there is more than one).
    final gap = nonZero > 1 ? 2 / rect.width * 2 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.001, sweep - gap),
        false,
        paint..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values.toString() != values.toString();
}

/// Cumulative registered users per month (area line, last point labelled).
class GrowthLine extends StatefulWidget {
  const GrowthLine({super.key, required this.data, this.height = 150});

  final List<({DateTime month, int total})> data;
  final double height;

  @override
  State<GrowthLine> createState() => _GrowthLineState();
}

class _GrowthLineState extends State<GrowthLine> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return SizedBox(height: widget.height);
    final sel = _selected ?? data.length - 1;
    final fmt = DateFormat('MMM');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: '${DateFormat('MMMM y').format(data[sel].month)}  ',
            style: const TextStyle(fontSize: 12, color: AppColors.gray),
            children: [
              TextSpan(
                text:
                    '${data[sel].total} user${data[sel].total == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final step = data.length == 1
                    ? c.maxWidth
                    : c.maxWidth / (data.length - 1);
                final i = (d.localPosition.dx / step).round().clamp(
                  0,
                  data.length - 1,
                );
                setState(() => _selected = i);
              },
              child: CustomPaint(
                size: Size(c.maxWidth, widget.height),
                painter: _LinePainter(
                  values: [for (final d in data) d.total],
                  selected: sel,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < data.length; i++)
              Text(
                fmt.format(data[i].month),
                style: TextStyle(
                  fontSize: 10.5,
                  color: i == sel ? AppColors.ink : AppColors.gray,
                  fontWeight: i == sel ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.selected});

  final List<int> values;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final maxV = values.fold<int>(0, math.max);
    final minV = values.fold<int>(maxV, math.min);
    final span = math.max(1, maxV - minV);
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
      values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1),
      pad + h - (values[i] - minV) / span * h * 0.85 - h * 0.075,
    );

    // Recessive grid.
    final grid = Paint()
      ..color = AppColors.mist
      ..strokeWidth = 1;
    for (var g = 0; g < 3; g++) {
      final y = pad + h * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.teal.withValues(alpha: 0.22),
            AppColors.teal.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      final p = at(i);
      final r = i == selected ? 6.0 : 4.0;
      canvas.drawCircle(p, r + 2, Paint()..color = AppColors.surface);
      canvas.drawCircle(p, r, Paint()..color = AppColors.teal);
    }
    // Selected guide.
    final s = at(selected);
    canvas.drawLine(
      Offset(s.dx, pad),
      Offset(s.dx, size.height),
      Paint()
        ..color = AppColors.teal.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.selected != selected || old.values.toString() != values.toString();
}

/// 14820 → 14.8k (dashboard headline numbers).
String _compact(int v) {
  if (v < 1000) return '$v';
  if (v < 1000000) {
    final k = v / 1000;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
  }
  return '${(v / 1000000).toStringAsFixed(1)}M';
}

String compactCount(int v) => _compact(v);

/// Demo revenue per week (one bar per week). Tap a bar to read its total.
class WeeklyRevenueBars extends StatefulWidget {
  const WeeklyRevenueBars({super.key, required this.data, this.height = 130});

  final List<({DateTime week, double total})> data;
  final double height;

  @override
  State<WeeklyRevenueBars> createState() => _WeeklyRevenueBarsState();
}

class _WeeklyRevenueBarsState extends State<WeeklyRevenueBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return SizedBox(height: widget.height);
    var max = 0.0;
    for (final d in data) {
      max = math.max(max, d.total);
    }
    final sel = _selected ?? data.length - 1;
    final fmt = DateFormat('MMM d');
    final money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Week of ${fmt.format(data[sel].week)}: ${money.format(data[sel].total)}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: max <= 0
                                ? 2
                                : math.max(
                                    2,
                                    (widget.height - 22) * data[i].total / max,
                                  ),
                            decoration: BoxDecoration(
                              color: i == sel
                                  ? AppColors.teal
                                  : AppColors.teal.withValues(alpha: 0.4),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fmt.format(data[i].week),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppColors.gray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
