import 'package:flutter/material.dart';

import '../models/user_model.dart';

/// Seller plan badge: blue Verified check + "Plus"/"Pro" pill. Renders
/// nothing for free (or lapsed) plans.
class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.profile, this.compact = false});

  final UserModel? profile;

  /// Compact: just the check + plan name, sized for inline name rows.
  final bool compact;

  static const Color verifiedBlue = Color(0xFF1D7FD8);

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null || !p.isVerifiedSeller) return const SizedBox.shrink();
    final label = p.isPro ? 'Pro' : 'Plus';
    return Tooltip(
      message: 'Verified $label seller',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: verifiedBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: compact ? 13 : 14, color: verifiedBlue),
            const SizedBox(width: 3),
            Text(
              compact ? label : 'Verified · $label',
              style: TextStyle(
                color: verifiedBlue,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
