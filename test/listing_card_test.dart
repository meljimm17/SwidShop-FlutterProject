// Home feed card in the real grid geometry at phone width and a large system
// font: any "BOTTOM OVERFLOWED" fails the test. Firebase-free (no images).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/models/listing_model.dart';
import 'package:swidshop/screens/customer/home_screen.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('ListingCard fits the 0.68 grid cell at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(720, 1560);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final soon = DateTime.now().add(const Duration(days: 3));
      final listings = [
        const ListingModel(
          listingId: 'a',
          sellerId: 's',
          title: 'Denim Trucker Jacket #9 with a very long vintage title',
          type: ListingType.buyNow,
          price: 4184,
        ),
        ListingModel(
          listingId: 'b',
          sellerId: 's',
          title: 'Silk Scarf #24',
          type: ListingType.bid,
          startingBid: 250,
          featuredUntil: soon,
          highlightUntil: soon,
        ),
        const ListingModel(
          listingId: 'c',
          sellerId: 's',
          title: 'Bucket Hat #23',
          type: ListingType.swap,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 780),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: listings.length,
                itemBuilder: (_, i) => ListingCard(listing: listings[i]),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ListingCard), findsNWidgets(3));
    });
  }
}
