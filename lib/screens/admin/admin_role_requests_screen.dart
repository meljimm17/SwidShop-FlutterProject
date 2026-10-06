import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/role_request_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import 'admin_widgets.dart';

/// Role-change requests from users (side bar → Role Requests). Approving
/// changes the user's role right away; their app updates live.
class AdminRoleRequestsScreen extends StatelessWidget {
  const AdminRoleRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final requests = admin.roleRequests;
    final pending = requests.where((r) => r.isPending).toList();
    final decided = requests.where((r) => !r.isPending).toList();
    if (requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No role requests yet. Users ask from Profile → Change role.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.gray),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          pending.isEmpty
              ? 'Nothing waiting'
              : '${pending.length} waiting for a decision',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final r in pending) ...[
          _RequestCard(request: r),
          const SizedBox(height: 10),
        ],
        if (decided.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Decided',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gray),
          ),
          const SizedBox(height: 10),
          for (final r in decided.take(30)) ...[
            _RequestCard(request: r),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request});

  final RoleRequestModel request;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _approve() async {
    final r = widget.request;
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final user = admin.user(r.uid);
    final activeListings = admin.listings
        .where((l) => l.sellerId == r.uid && l.status.value == 'active')
        .length;
    final losesShop = !r.requestedRole.canSell && activeListings > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Make ${admin.nameOf(r.uid)} ${r.requestedRole.label}?'),
        content: Text(
          '${user?.role.label ?? r.currentRole.label} → '
          '${r.requestedRole.label}. Their features change immediately.'
          '${losesShop ? '\n\nThey have $activeListings active listing(s); '
              'those stay up, but they lose the Seller Centre.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => admin.firestore.approveRoleRequest(r, adminUid: adminUid));
  }

  Future<void> _reject() async {
    final r = widget.request;
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Decline this request?'),
        content: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note to the user (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    final note = ctrl.text;
    ctrl.dispose();
    if (ok != true || !mounted) return;
    await _run(
      () => admin.firestore.rejectRoleRequest(r, adminUid: adminUid, note: note),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('roleRequest: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final admin = context.watch<AdminProvider>();
    final user = admin.user(r.uid);
    final (statusText, statusColor) = switch (r.status) {
      RoleRequestStatus.pending => ('Pending', AppColors.amber),
      RoleRequestStatus.approved => ('Approved', AppColors.green),
      RoleRequestStatus.rejected => ('Declined', AppColors.gray),
    };
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(user: user, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      admin.nameOf(r.uid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      user?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              SoftPill(statusText, color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RolePill(r.currentRole),
              const Icon(Icons.arrow_forward, size: 18, color: AppColors.gray),
              _RolePill(r.requestedRole, highlight: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Requested ${r.createdAt == null ? 'just now' : timeago.format(r.createdAt!)}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.gray),
          ),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '“${r.reason}”',
              style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4),
            ),
          ],
          if (!r.isPending && r.adminNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note: ${r.adminNote}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _approve,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.teal,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill(this.role, {this.highlight = false});

  final UserRole role;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.coralDeep : AppColors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
