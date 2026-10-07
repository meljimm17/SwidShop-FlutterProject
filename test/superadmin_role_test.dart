import 'package:flutter_test/flutter_test.dart';
import 'package:swidshop/models/admin_audit_entry.dart';
import 'package:swidshop/models/system_announcement.dart';
import 'package:swidshop/models/user_model.dart';
import 'package:swidshop/providers/admin_provider.dart';
import 'package:swidshop/screens/admin/admin_shell.dart';
import 'package:swidshop/screens/auth/role_home.dart';
import 'package:swidshop/services/auth_service.dart';

void main() {
  test('superadmin role maps and routes to the admin console', () {
    expect(UserRole.fromValue('superadmin'), UserRole.superadmin);
    expect(UserRole.superadmin.label, 'Superadmin');
    expect(homeForRole(UserRole.superadmin), isA<AdminShell>());
    expect(UserRole.superadmin.canUseMarketplace, isFalse);
    expect(UserRole.superadmin.canSell, isFalse);
    expect(UserRole.admin.canUseMarketplace, isFalse);
    expect(UserRole.admin.canSell, isFalse);
    expect(UserRole.customer.canUseMarketplace, isTrue);
    expect(UserRole.both.canSell, isTrue);
  });

  test(
    'administrator dialog accepts only the two configured demo accounts',
    () {
      expect(AuthService.isAdministratorLogin('admin', 'admin123'), isTrue);
      expect(
        AuthService.isAdministratorLogin('superadmin', 'superadmin123'),
        isTrue,
      );
      expect(
        AuthService.isAdministratorLogin('superadmin', 'wrong-password'),
        isFalse,
      );
    },
  );

  test('admin role statistics count superadmins separately', () {
    final counts = AdminStats.roleCounts([
      const UserModel(
        uid: 's',
        name: 'Root',
        email: 'root@example.com',
        role: UserRole.superadmin,
      ),
      const UserModel(
        uid: 'a',
        name: 'Staff',
        email: 'staff@example.com',
        role: UserRole.admin,
      ),
    ]);

    expect(counts[UserRole.superadmin], 1);
    expect(counts[UserRole.admin], 1);
  });

  test(
    'public announcement uses safe defaults and reads configured fields',
    () {
      expect(SystemAnnouncement.fromMap(null).enabled, isFalse);
      final announcement = SystemAnnouncement.fromMap({
        'announcementEnabled': true,
        'announcementMessage': 'Marketplace update',
      });
      expect(announcement.enabled, isTrue);
      expect(announcement.message, 'Marketplace update');
    },
  );

  test('audit entry parses recorded action fields', () {
    final entry = AdminAuditEntry.fromMap('entry-1', {
      'actorUid': 'admin-uid',
      'action': 'account_status_changed',
      'targetType': 'user',
      'targetId': 'user-uid',
      'summary': 'Suspended account.',
    });
    expect(entry.id, 'entry-1');
    expect(entry.actorUid, 'admin-uid');
    expect(entry.summary, 'Suspended account.');
  });
}
