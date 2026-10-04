import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/rating_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';

/// Reviews other users left for me (Phase 3.11).
class MyRatingsScreen extends StatelessWidget {
  const MyRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'My Ratings & Reviews'),
      body: StreamBuilder<List<RatingModel>>(
        stream: FirestoreService().streamRatingsForUser(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ratings = snap.data ?? const <RatingModel>[];
          if (ratings.isEmpty) {
            return const Center(
              child: Text(
                'No reviews yet — complete a deal to earn one.',
                style: TextStyle(color: AppColors.gray),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ratings.length,
            itemBuilder: (context, i) {
              final r = ratings[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: UserNameText(
                              r.raterId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StarRatingDisplay(
                            rating: r.stars.toDouble(),
                            size: 14,
                          ),
                        ],
                      ),
                      if (r.comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          r.comment,
                          style: const TextStyle(height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        r.createdAt == null
                            ? ''
                            : AppUtils.formatDate(r.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
