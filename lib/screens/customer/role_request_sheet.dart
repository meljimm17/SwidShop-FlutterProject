import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/role_request_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

/// What each role can do (shown when choosing a role to request).
String roleBlurb(UserRole role) => switch (role) {
      UserRole.customer => 'Buy, bid and swap. No shop.',
      UserRole.both => 'Run your own shop AND buy, bid and swap.',
      UserRole.admin => '',
    };

/// Profile tile: current role + request status; tap to request a change.
class RoleRequestTile extends StatelessWidget {
  const RoleRequestTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.firebaseUser?.uid ?? '';
    final role = auth.profile?.role ?? UserRole.customer;
    if (uid.isEmpty || role == UserRole.admin) return const SizedBox.shrink();
    return StreamBuilder<RoleRequestModel?>(
      stream: FirestoreService().streamMyRoleRequest(uid),
      builder: (context, snap) {
        final req = snap.data;
        final pending = req != null && req.isPending;
        final String subtitle;
        if (pending) {
          subtitle = 'Waiting for admin: ${req.currentRole.label} → '
              '${req.requestedRole.label}';
        } else if (req != null &&
            req.status == RoleRequestStatus.rejected &&
            req.requestedRole != role) {
          subtitle = 'Last request declined'
              '${req.adminNote.isEmpty ? '' : ': ${req.adminNote}'}';
        } else {
          subtitle = 'You are ${role.label}. Tap to request a change.';
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            pending ? Icons.hourglass_top_rounded : Icons.badge_outlined,
            color: pending ? AppColors.amber : AppColors.ink,
          ),
          title: const Text(
            'Change role',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right, color: AppColors.gray),
          onTap: () => showRoleRequestSheet(context, existing: req),
        );
      },
    );
  }
}

/// Opens the request sheet (or the pending request with a Cancel option).
Future<void> showRoleRequestSheet(
  BuildContext context, {
  RoleRequestModel? existing,
  UserRole? suggested,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => _RoleRequestSheet(existing: existing, suggested: suggested),
  );
}

class _RoleRequestSheet extends StatefulWidget {
  const _RoleRequestSheet({this.existing, this.suggested});

  final RoleRequestModel? existing;
  final UserRole? suggested;

  @override
  State<_RoleRequestSheet> createState() => _RoleRequestSheetState();
}

class _RoleRequestSheetState extends State<_RoleRequestSheet> {
  final _reasonCtrl = TextEditingController();
  UserRole? _choice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _choice = widget.suggested;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String uid, UserRole current) async {
    final choice = _choice;
    if (choice == null || choice == current || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreService().submitRoleRequest(
        uid: uid,
        currentRole: current,
        requestedRole: choice,
        reason: _reasonCtrl.text,
      );
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Request sent — an admin will review it.'),
        ),
      );
    } catch (e) {
      debugPrint('submitRoleRequest: $e');
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Could not send. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _cancel(String uid) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreService().cancelRoleRequest(uid);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    } catch (e) {
      debugPrint('cancelRoleRequest: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.firebaseUser?.uid ?? '';
    final current = auth.profile?.role ?? UserRole.customer;
    final pending = widget.existing?.isPending ?? false;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change role',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'You are ${current.label}. An admin reviews every request; '
              'your features change as soon as it is approved.',
              style: const TextStyle(color: AppColors.gray, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (pending) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Waiting for admin approval: '
                  '${widget.existing!.requestedRole.label}'
                  '${widget.existing!.reason.isEmpty ? '' : '\n“${widget.existing!.reason}”'}',
                  style: const TextStyle(height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _busy ? null : () => _cancel(uid),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel request'),
              ),
            ] else ...[
              for (final role in RoleRequestModel.requestable)
                if (role != current)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RoleOption(
                      role: role,
                      selected: _choice == role,
                      onTap: _busy ? null : () => setState(() => _choice = role),
                    ),
                  ),
              const SizedBox(height: 4),
              TextField(
                controller: _reasonCtrl,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Why? (optional)',
                  hintText: 'e.g. I also want to buy items',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: (_busy || _choice == null || _choice == current)
                    ? null
                    : () => _submit(uid, current),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send request'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.coral : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.coral : AppColors.gray,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    roleBlurb(role),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
