import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/top_app_bar.dart';
import 'home_screen.dart' show ListingCard;

/// Grid of the user's hearted listings (Phase 3.11).
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favorites =
        context.watch<AuthProvider>().profile?.favorites ?? const [];
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'Favorites'),
      body: favorites.isEmpty
          ? const Center(
              child: Text(
                'Nothing saved yet — tap the heart on any listing.',
                style: TextStyle(color: AppColors.gray),
              ),
            )
          : FutureBuilder<List<ListingModel?>>(
              future: Future.wait(
                favorites.map(
                  (id) => FirestoreService().getListing(id),
                ),
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = (snap.data ?? const [])
                    .whereType<ListingModel>()
                    .toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Saved listings are gone.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      ListingCard(listing: items[i]),
                );
              },
            ),
    );
  }
}
