import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/listing_model.dart';

/// Colored pill showing how a listing is acquired.
///
/// * Buy Now → coral
/// * Bidding → amber
/// * Swap    → teal
class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});

  final ListingType type;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    switch (type) {
      case ListingType.buyNow:
        color = AppColors.coral;
        label = 'Buy Now';
      case ListingType.bid:
        color = AppColors.amber;
        label = 'Bidding';
      case ListingType.swap:
        color = AppColors.teal;
        label = 'Swap';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
