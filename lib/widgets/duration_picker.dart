import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';

/// Days / hours / minutes picker. Returns the chosen [Duration] (null when
/// cancelled). The OK button stays disabled outside [min]..[max].
Future<Duration?> showDurationPicker(
  BuildContext context, {
  required Duration initial,
  required Duration min,
  required Duration max,
  String title = 'Auction length',
  String? helper,
}) {
  return showDialog<Duration>(
    context: context,
    builder: (_) => _DurationPickerDialog(
      initial: initial,
      min: min,
      max: max,
      title: title,
      helper: helper,
    ),
  );
}

class _DurationPickerDialog extends StatefulWidget {
  const _DurationPickerDialog({
    required this.initial,
    required this.min,
    required this.max,
    required this.title,
    this.helper,
  });

  final Duration initial;
  final Duration min;
  final Duration max;
  final String title;
  final String? helper;

  @override
  State<_DurationPickerDialog> createState() => _DurationPickerDialogState();
}

class _DurationPickerDialogState extends State<_DurationPickerDialog> {
  late int _days = widget.initial.inDays;
  late int _hours = widget.initial.inHours % 24;
  late int _minutes = widget.initial.inMinutes % 60;

  Duration get _value =>
      Duration(days: _days, hours: _hours, minutes: _minutes);

  String? get _problem {
    if (_value < widget.min) {
      return 'At least ${AppUtils.formatDuration(widget.min)}.';
    }
    if (_value > widget.max) {
      return 'At most ${AppUtils.formatDuration(widget.max)}.';
    }
    return null;
  }

  Widget _stepper(
    String unit,
    int value,
    int maxValue,
    int step,
    ValueChanged<int> onChanged,
  ) {
    Widget btn(IconData icon, int next) => IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
          onPressed: next < 0 || next > maxValue
              ? null
              : () => setState(() => onChanged(next)),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.keyboard_arrow_up_rounded, value + step),
        Text(
          '$value',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        Text(unit, style: const TextStyle(color: AppColors.gray)),
        btn(Icons.keyboard_arrow_down_rounded, value - step),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.helper != null) ...[
            Text(
              widget.helper!,
              style: const TextStyle(color: AppColors.gray, height: 1.4),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stepper('days', _days, widget.max.inDays, 1, (v) => _days = v),
              _stepper('hours', _hours, 23, 1, (v) => _hours = v),
              _stepper('min', _minutes, 55, 5, (v) => _minutes = v),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            problem ?? AppUtils.formatDuration(_value),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: problem == null ? AppColors.teal : AppColors.red,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              problem == null ? () => Navigator.of(context).pop(_value) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
