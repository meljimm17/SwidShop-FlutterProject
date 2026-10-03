import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../core/theme.dart';
import '../core/utils.dart';

/// Read-only star rating with an optional review count.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.reviewCount,
    this.size = 16,
  });

  final double rating;
  final int? reviewCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RatingBarIndicator(
          rating: rating.clamp(0, 5),
          itemSize: size,
          itemPadding: const EdgeInsets.symmetric(horizontal: 1),
          unratedColor: AppColors.gray.withValues(alpha: 0.4),
          itemBuilder: (context, _) =>
              const Icon(Icons.star, color: AppColors.amber),
        ),
        const SizedBox(width: 6),
        Text(
          AppUtils.roundRating(rating).toStringAsFixed(1),
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        if (reviewCount != null) ...[
          const SizedBox(width: 4),
          Text(
            '($reviewCount)',
            style: const TextStyle(color: AppColors.gray, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
