import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/report_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/trusted_badge.dart';
import 'admin_gate.dart';

/// Browse, suspend and ban accounts (Phase 4.2).
///
/// Suspended/banned users are signed out by the app on next profile sync
/// (interim client-side enforcement — token revocation needs the function).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _firestore = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _roleTab = 'All';
  String _query = '';
  int _visible = 25;

  static const _page = 25;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: const TopAppBar(title: 'Manage Users'),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search name or email',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _query = '';
                              _visible = _page;
                            });
                          },
                        ),
                ),
                onChanged: (v) => setState(() {
                  _query = v.trim().toLowerCase();
                  _visible = _page;
                }),
              ),
            ),
            _tabs(),
            Expanded(
              child: StreamBuilder<List<UserModel>>(
                stream: _firestore.streamAllUsers(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var users = snap.data ?? const <UserModel>[];
                  final banned = users
                      .where((u) =>
                          u.accountStatus == AccountStatus.banned)
                      .length;
                  if (_roleTab != 'All') {
                    final role = UserRole.fromValue(
                      _roleTab.toLowerCase(),
                    );
                    users = users.where((u) => u.role == role).toList();
                  }
                  if (_query.isNotEmpty) {
                    users = users
                        .where((u) =>
                            u.name.toLowerCase().contains(_query) ||
                            u.email.toLowerCase().contains(_query))
                        .toList();
                  }
                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        'No users match.',
                        style: TextStyle(color: AppColors.gray),
                      ),
                    );
                  }
                  final shown = users.take(_visible).toList();
                  return Column(
                    children: [
                      _countLine(shown.length, users.length, banned),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: shown.length +
                              (users.length > _visible ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= shown.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _visible += _page,
                                  ),
                                  child: Text(
                                    'Load more (${users.length - _visible} left)',
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: _row(shown[i]),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    const tabs = ['All', 'Customer', 'Seller', 'Both'];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t),
                selected: _roleTab == t,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _roleTab = t;
                  _visible = _page;
                }),
                selectedColor: AppColors.teal,
                labelStyle: TextStyle(
                  color: _roleTab == t ? Colors.white : AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color:
                      _roleTab == t ? AppColors.teal : AppColors.line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "Showing X of Y · Z banned" (mockup footer counts, all live).
  Widget _countLine(int shown, int total, int banned) {
    return StreamBuilder<List<ReportModel>>(
      stream: _firestore.streamReportsByStatus(ReportStatus.pending),
      builder: (context, snap) {
        final flagged = (snap.data ?? const <ReportModel>[])
            .where((r) => r.targetType == ReportTargetType.user)
            .map((r) => r.targetId)
            .toSet()
            .length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Showing $shown of $total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.gray,
                  ),
                ),
              ),
              if (flagged > 0)
                Text(
                  '$flagged flagged',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '$banned banned',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.gray,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(UserModel user) {
    return AppCardWrapper(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _UserDetail(uid: user.uid),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.cream,
            backgroundImage: user.photoUrl.isNotEmpty
                ? NetworkImage(user.photoUrl)
                : null,
            child: user.photoUrl.isEmpty
                ? const Icon(Icons.person_outline, color: AppColors.gray)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name.isEmpty ? 'Unnamed' : user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (user.trustedBadge) ...[
                      const SizedBox(width: 6),
                      const TrustedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.role.value} · ★ ${user.avgRating.toStringAsFixed(1)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ],
            ),
          ),
          _statusPill(user.accountStatus),
        ],
      ),
    );
  }

  Widget _statusPill(AccountStatus status) {
    final color = switch (status) {
      AccountStatus.active => AppColors.green,
      AccountStatus.suspended => AppColors.amber,
      AccountStatus.banned => AppColors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        status.value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Full profile + history + moderation actions for one account.
class _UserDetail extends StatefulWidget {
  const _UserDetail({required this.uid});

  final String uid;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  final _firestore = FirestoreService();
  bool _busy = false;

  Future<void> _setStatus(AccountStatus status) async {
    final label = status == AccountStatus.active
        ? 'Re-activate'
        : status.value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('$label this account?'),
        content: status == AccountStatus.active
            ? const Text('They will be able to sign in again.')
            : Text(
                'They will be signed out and blocked from signing in '
                '(${status.value}).',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _firestore.updateAccountStatus(widget.uid, status);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('updateAccountStatus: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update. Try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scroll) => StreamBuilder<UserModel?>(
          stream: _firestore.streamUser(widget.uid),
          builder: (context, snap) {
            final user = snap.data;
            if (user == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.cream,
                      backgroundImage: user.photoUrl.isNotEmpty
                          ? NetworkImage(user.photoUrl)
                          : null,
                      child: user.photoUrl.isEmpty
                          ? const Icon(Icons.person_outline,
                              color: AppColors.gray, size: 30)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name.isEmpty ? 'Unnamed' : user.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            user.email,
                            style: const TextStyle(
                              color: AppColors.gray,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          StarRatingDisplay(
                            rating: user.avgRating,
                            reviewCount: user.completedTransactions,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Role: ${user.role.value} · Status: ${user.accountStatus.value} · '
                  'Trust: ${(user.completionRate * 100).toStringAsFixed(0)}% '
                  '(${user.completedTransactions} deals)',
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.gray),
                ),
                Text(
                  'Member since ${AppUtils.formatDate(user.createdAt)}',
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.gray),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Deals',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _history(user.uid),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (user.accountStatus != AccountStatus.active)
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _setStatus(AccountStatus.active),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.green,
                          ),
                          child: const Text('Re-activate'),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _setStatus(AccountStatus.suspended),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.amber,
                            side: const BorderSide(color: AppColors.amber),
                          ),
                          child: const Text('Suspend'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _setStatus(AccountStatus.banned),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.red,
                          ),
                          child: const Text('Ban'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _history(String uid) {
    return FutureBuilder<List<TransactionModel>>(
      future: Future.wait([
        _firestore.streamBuyerTransactions(uid).first,
        _firestore.streamSellerTransactions(uid).first,
      ]).then((lists) => [...lists[0], ...lists[1]]),
      builder: (context, snap) {
        final txns = snap.data ?? const <TransactionModel>[];
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (txns.isEmpty) {
          return const Text(
            'No deals yet.',
            style: TextStyle(color: AppColors.gray),
          );
        }
        return Column(
          children: [
            for (final t in txns.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.listingTitle.isEmpty ? t.orderNumber : t.listingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    StatusPill.transaction(t.status),
                  ],
                ),
              ),
            if (txns.length > 10)
              Text(
                '+ ${txns.length - 10} more',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.gray,
                ),
              ),
          ],
        );
      },
    );
  }
}
