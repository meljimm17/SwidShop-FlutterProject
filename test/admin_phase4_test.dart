// Phase 4 pure-logic tests (no Firebase — see AGENTS.md testing rule).

import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/models/report_model.dart';
import 'package:swidshop/models/user_model.dart';

void main() {
  group('AccountStatus', () {
    test('defaults to active on older docs', () {
      const user = UserModel(uid: 'u1', name: 'N', email: 'e');
      final map = user.toMap()..remove('accountStatus');
      expect(UserModel.fromMap('u1', map).accountStatus, AccountStatus.active);
      expect(UserModel.fromMap('u1', const {}).accountStatus,
          AccountStatus.active);
    });

    test('round-trips suspended/banned', () {
      const suspended = UserModel(
        uid: 'u1',
        name: 'N',
        email: 'e',
        accountStatus: AccountStatus.suspended,
      );
      expect(
        UserModel.fromMap('u1', suspended.toMap()).accountStatus,
        AccountStatus.suspended,
      );
      const banned = UserModel(
        uid: 'u1',
        name: 'N',
        email: 'e',
        accountStatus: AccountStatus.banned,
      );
      expect(
        UserModel.fromMap('u1', banned.toMap()).accountStatus,
        AccountStatus.banned,
      );
    });

    test('copyWith replaces the status', () {
      const user = UserModel(uid: 'u1', name: 'N', email: 'e');
      expect(
        user.copyWith(accountStatus: AccountStatus.banned).accountStatus,
        AccountStatus.banned,
      );
    });
  });

  group('Trusted Seller review state', () {
    test('reads eligibility and unresolved-report count from server fields', () {
      final user = UserModel.fromMap('seller1', {
        'name': 'Seller',
        'trustedBadgeEligible': true,
        'trustedOpenReports': 0,
      });
      expect(user.trustedBadgeEligible, isTrue);
      expect(user.trustedOpenReports, 0);
      expect(user.copyWith(trustedBadgeEligible: false).trustedBadgeEligible,
          isFalse);
    });

    test('legacy accounts default to not eligible', () {
      final user = UserModel.fromMap('seller1', const {});
      expect(user.trustedBadgeEligible, isFalse);
      expect(user.trustedOpenReports, 0);
    });
  });

  group('ReportTargetType', () {
    test('parses the rating target (Phase 4.7)', () {
      expect(ReportTargetType.fromValue('rating'), ReportTargetType.rating);
      expect(ReportTargetType.fromValue('listing'), ReportTargetType.listing);
      expect(ReportTargetType.fromValue('user'), ReportTargetType.user);
      expect(ReportTargetType.fromValue(null), ReportTargetType.user);
    });

    test('rating reports round-trip', () {
      const report = ReportModel(
        reportId: 'r1',
        reportedBy: 'u9',
        targetType: ReportTargetType.rating,
        targetId: 'rate1',
        reason: 'fake review',
      );
      final restored = ReportModel.fromMap('r1', {
        ...report.toMap(),
        'createdAt': null,
      });
      expect(restored.targetType, ReportTargetType.rating);
      expect(restored.targetId, 'rate1');
      expect(restored.status, ReportStatus.pending);
    });
  });
}
