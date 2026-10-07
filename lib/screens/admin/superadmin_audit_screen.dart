import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/admin_audit_entry.dart';
import '../../providers/admin_provider.dart';
import 'admin_widgets.dart';

class SuperadminAuditScreen extends StatelessWidget {
  const SuperadminAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminAuditEntry>>(
      stream: context.read<AdminProvider>().firestore.streamAdminAuditLogs(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load audit logs.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'No admin actions have been recorded yet.',
              style: TextStyle(color: AppColors.gray),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text(
              'System audit logs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Recent recorded admin changes. Entries cannot be edited or '
              'deleted from the app.',
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.action.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.coralDeep,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.summary,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'By ${entry.actorUid} · ${entry.targetType}'
                        '${entry.targetId.isEmpty ? '' : ' ${entry.targetId}'}',
                        style: const TextStyle(
                          color: AppColors.gray,
                          fontSize: 11,
                        ),
                      ),
                      if (entry.createdAt != null)
                        Text(
                          DateFormat.yMMMd().add_jm().format(entry.createdAt!),
                          style: const TextStyle(
                            color: AppColors.gray,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
