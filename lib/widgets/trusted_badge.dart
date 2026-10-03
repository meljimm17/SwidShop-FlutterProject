import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Green checkmark + "Trusted" label shown for verified sellers.
class TrustedBadge extends StatelessWidget {
  const TrustedBadge({super.key, this.compact = false});

  /// Compact mode shows only the check icon (e.g. inline beside a name).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Icon(Icons.verified, color: AppColors.green, size: 18);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: AppColors.green, size: 14),
          SizedBox(width: 4),
          Text(
            'Trusted',
            style: TextStyle(
              color: AppColors.green,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
