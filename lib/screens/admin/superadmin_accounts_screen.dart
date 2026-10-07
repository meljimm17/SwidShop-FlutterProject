import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import 'admin_widgets.dart';

class SuperadminAccountsScreen extends StatelessWidget {
  const SuperadminAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final users = context.watch<AdminProvider>().users;
    final currentUid = context.watch<AuthProvider>().firebaseUser?.uid;
    final candidates = users
        .where(
          (user) => user.role != UserRole.superadmin && user.uid != currentUid,
        )
        .toList();
    final fs = context.read<AdminProvider>().firestore;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Text(
          'Manage admin accounts',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Grant admin access to an existing account or revoke it. '
          'Superadmin accounts are not manageable here.',
          style: TextStyle(color: AppColors.gray),
        ),
        const SizedBox(height: 16),
        if (candidates.isEmpty)
          const AdminCard(
            child: Text('No eligible accounts are available yet.'),
          )
        else
          for (final user in candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminCard(
                child: Row(
                  children: [
                    AdminAvatar(user: user, size: 44, showStatus: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name.isEmpty ? user.email : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            user.role == UserRole.admin
                                ? '${user.email} · Admin'
                                : '${user.email} · ${user.role.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.gray,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _changeRole(
                        context,
                        fs,
                        user,
                        makeAdmin: user.role != UserRole.admin,
                      ),
                      child: Text(
                        user.role == UserRole.admin ? 'Revoke' : 'Grant',
                        style: TextStyle(
                          color: user.role == UserRole.admin
                              ? AppColors.red
                              : AppColors.coralDeep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    FirestoreService fs,
    UserModel user, {
    required bool makeAdmin,
  }) async {
    final action = makeAdmin
        ? 'Grant admin access to'
        : 'Revoke admin access from';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(makeAdmin ? 'Grant admin access?' : 'Revoke admin access?'),
        content: Text('$action ${user.name.isEmpty ? user.email : user.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(makeAdmin ? 'Grant access' : 'Revoke access'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    try {
      await fs.setManagedAdminRole(user.uid, makeAdmin: makeAdmin);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              makeAdmin ? 'Admin access granted.' : 'Admin access revoked.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update admin access: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
}
