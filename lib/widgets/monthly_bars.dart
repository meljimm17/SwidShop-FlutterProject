import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';

/// Single-series monthly bar chart (e.g. ₱ settled per month).
///
/// One hue, 4px rounded tops anchored to the baseline, small gaps between
/// bars, zero months drawn as a thin stub so the timeline stays readable.
/// Tapping a bar shows its month and exact value; the latest month is
/// selected by default. Month labels are optional ([showLabels]).
class MonthlyBars extends StatefulWidget {
  const MonthlyBars({
    super.key,
    required this.data,
    this.height = 120,
    this.color = AppColors.teal,
    this.showLabels = true,
    this.interactive = true,
    this.onDark = false,
  });

  final List<({DateTime month, double total})> data;
  final double height;
  final Color color;
  final bool showLabels;
  final bool interactive;

  /// Use light text/stub colours on a dark card.
  final bool onDark;

  @override
  State<MonthlyBars> createState() => _MonthlyBarsState();
}

class _MonthlyBarsState extends State<MonthlyBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return SizedBox(height: widget.height);
    final max = data.fold<double>(0, (m, d) => d.total > m ? d.total : m);
    final sel = _selected ?? data.length - 1;
    final ink = widget.onDark ? Colors.white : AppColors.ink;
    final muted = widget.onDark ? Colors.white60 : AppColors.gray;
    final stub = widget.onDark ? Colors.white24 : AppColors.line;
    final monthFmt = DateFormat('MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.interactive)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                text: '${DateFormat('MMMM y').format(data[sel].month)}  ',
                style: TextStyle(fontSize: 12, color: muted),
                children: [
                  TextSpan(
                    text: AppUtils.formatCurrency(data[sel].total),
                    style: TextStyle(fontWeight: FontWeight.w800, color: ink),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.interactive
                        ? () => setState(() => _selected = i)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          height: max <= 0 || data[i].total <= 0
                              ? 3
                              : (data[i].total / max * widget.height).clamp(
                                  4.0,
                                  widget.height,
                                ),
                          decoration: BoxDecoration(
                            color: data[i].total <= 0
                                ? stub
                                : widget.color.withValues(
                                    alpha: !widget.interactive || i == sel
                                        ? 1
                                        : 0.45,
                                  ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showLabels) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: Text(
                    monthFmt.format(data[i].month),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == sel && widget.interactive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == sel && widget.interactive ? ink : muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
