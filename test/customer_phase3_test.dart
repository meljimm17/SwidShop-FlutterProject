// Phase 3 pure-logic tests (no Firebase — see AGENTS.md testing rule).

import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/models/notification_model.dart';
import 'package:swidshop/models/user_model.dart';
import 'package:swidshop/screens/customer/notifications_screen.dart'
    show parseRelatedId;

void main() {
  group('parseRelatedId', () {
    test('splits kind and id on the first colon', () {
      expect(
        parseRelatedId('listing:abc123'),
        (kind: 'listing', id: 'abc123'),
      );
      expect(
        parseRelatedId('transaction:swap_offer1'),
        (kind: 'transaction', id: 'swap_offer1'),
      );
      expect(
        parseRelatedId('offer:xyz'),
        (kind: 'offer', id: 'xyz'),
      );
    });

    test('legacy bare ids degrade gracefully', () {
      final parsed = parseRelatedId('abc123');
      expect(parsed.id, 'abc123');
      expect(parsed.kind, isEmpty);
    });
  });

  group('UserModel favorites/following', () {
    test('round-trips through toMap/fromMap', () {
      const user = UserModel(
        uid: 'u1',
        name: 'Buyer',
        email: 'b@example.com',
        favorites: ['l1', 'l2'],
        following: ['s9'],
      );
      final restored = UserModel.fromMap('u1', user.toMap());
      expect(restored.favorites, ['l1', 'l2']);
      expect(restored.following, ['s9']);
    });

    test('defaults to empty on older docs', () {
      const user = UserModel(uid: 'u1', name: 'N', email: 'e');
      final map = user.toMap()..remove('favorites')..remove('following');
      final restored = UserModel.fromMap('u1', map);
      expect(restored.favorites, isEmpty);
      expect(restored.following, isEmpty);
    });

    test('copyWith replaces the lists', () {
      const user = UserModel(uid: 'u1', name: 'N', email: 'e');
      final next = user.copyWith(favorites: ['l5']);
      expect(next.favorites, ['l5']);
      expect(next.following, isEmpty);
    });
  });

  test('NotificationModel keeps the link convention intact', () {
    const n = NotificationModel(
      type: NotificationType.outbid,
      message: 'Outbid!',
      relatedId: 'listing:abc123',
    );
    final restored =
        NotificationModel.fromMap('n1', {...n.toMap(), 'read': false});
    expect(restored.relatedId, 'listing:abc123');
    expect(parseRelatedId(restored.relatedId).id, 'abc123');
  });
}
