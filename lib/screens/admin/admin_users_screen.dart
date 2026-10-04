import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/report_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../shared/transaction_chat_screen.dart';
import 'admin_gate.dart';
import 'admin_widgets.dart';

/// Pushes the full-screen user detail panel, carrying the shell's
/// [AdminProvider] into the new route.
void openAdminUserDetail(BuildContext context, String uid) {
  final admin = context.read<AdminProvider>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: admin,
        child: AdminGate(child: AdminUserDetailScreen(uid: uid)),
      ),
    ),
  );
}

/// Suspend / ban / re-activate with confirmation. Returns true on success.
Future<bool> setAccountStatusFlow(
  BuildContext context,
  UserModel user,
  AccountStatus status,
) async {
  final name = user.name.isEmpty ? user.email : user.name;
  final ok = await confirmAdminAction(
    context,
    title: switch (status) {
      AccountStatus.active => 'Re-activate $name?',
      AccountStatus.suspended => 'Suspend $name?',
      AccountStatus.banned => 'Ban $name?',
    },
    message: status == AccountStatus.active
        ? 'They will be able to sign in again.'
        : 'They are signed out on their next sync and blocked from '
              'signing in until an admin re-activates the account.',
    confirmLabel: switch (status) {
      AccountStatus.active => 'Re-activate',
      AccountStatus.suspended => 'Suspend',
      AccountStatus.banned => 'Ban',
    },
    destructive: status != AccountStatus.active,
  );
  if (!ok || !context.mounted) return false;
  try {
    await context.read<AdminProvider>().firestore.updateAccountStatus(
      user.uid,
      status,
    );
    return true;
  } catch (e) {
    debugPrint('updateAccountStatus: $e');
    if (context.mounted) {
      showAdminError(context, 'Could not update. Try again.');
    }
    return false;
  }
}

/// Users tab: search, role pills with live counts, moderation tiles and
/// paged user cards (Phase 4.2).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  UserRole? _role;
  String _query = '';
  int _page = 0;

  static const _pageSize = 10;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final roles = AdminStats.roleCounts(a.users);
    final flagged = a.flaggedUserIds;
    final sellers = a.users.where(
      (u) => u.role == UserRole.seller || u.role == UserRole.both,
    );
    final activeSellers = sellers
        .where((u) => u.accountStatus == AccountStatus.active)
        .length;
    final banned = a.users
        .where((u) => u.accountStatus == AccountStatus.banned)
        .length;
    final bannedRate = a.users.isEmpty ? 0.0 : banned / a.users.length * 100;

    var list = a.users;
    if (_role != null) list = list.where((u) => u.role == _role).toList();
    if (_query.isNotEmpty) {
      list = list
          .where(
            (u) =>
                u.name.toLowerCase().contains(_query) ||
                u.email.toLowerCase().contains(_query) ||
                u.uid.toLowerCase().contains(_query),
          )
          .toList();
    }
    // Flagged accounts first, then newest (stream order).
    list = [
      ...list.where((u) => flagged.contains(u.uid)),
      ...list.where((u) => !flagged.contains(u.uid)),
    ];
    final pages = math.max(1, (list.length / _pageSize).ceil());
    final page = math.min(_page, pages - 1);
    final shown = list.skip(page * _pageSize).take(_pageSize).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: AdminSearchField(
            controller: _searchCtrl,
            hint: 'Search name, email, user ID…',
            onChanged: (v) => setState(() {
              _query = v.trim().toLowerCase();
              _page = 0;
            }),
          ),
        ),
        PillRow<UserRole?>(
          selected: _role,
          onSelected: (r) => setState(() {
            _role = r;
            _page = 0;
          }),
          options: [
            PillOption(null, 'All Users (${a.users.length})'),
            PillOption(
              UserRole.customer,
              'Customer (${roles[UserRole.customer]})',
            ),
            PillOption(UserRole.seller, 'Seller (${roles[UserRole.seller]})'),
            PillOption(UserRole.both, 'Both (${roles[UserRole.both]})'),
            PillOption(UserRole.admin, 'Admin (${roles[UserRole.admin]})'),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Tile(
                    label: 'Flagged Queue',
                    value: '${flagged.length}',
                    caption: 'need review',
                    color: AppColors.coralDeep,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(
                    label: 'Active Sellers',
                    value: '$activeSellers',
                    caption: 'of ${sellers.length}',
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(
                    label: 'Banned Rate',
                    value: '${bannedRate.toStringAsFixed(1)}%',
                    caption: bannedRate < 2 ? 'low risk' : 'elevated',
                    color: AppColors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No users match.',
                style: TextStyle(color: AppColors.gray),
              ),
            ),
          ),
        for (final u in shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _UserCard(
              user: u,
              pending: AdminStats.pendingFor(a.reports, u.uid),
              strikes: AdminStats.strikesFor(a.reports, u.uid),
            ),
          ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _Pager(
              page: page,
              pages: pages,
              onPage: (p) => setState(() => _page = p),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      radius: 12,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.pending,
    required this.strikes,
  });

  final UserModel user;
  final int pending;
  final int strikes;

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthProvider>().firebaseUser?.uid;
    final isAdmin = user.role == UserRole.admin;
    final banned = user.accountStatus == AccountStatus.banned;
    final statusLabel = switch (user.accountStatus) {
      AccountStatus.active => isAdmin ? 'Active Staff' : 'Active',
      AccountStatus.suspended =>
        pending + strikes > 0
            ? 'Suspended (${pending + strikes} report${pending + strikes == 1 ? '' : 's'})'
            : 'Suspended',
      AccountStatus.banned =>
        strikes > 0
            ? 'Banned ($strikes strike${strikes == 1 ? '' : 's'})'
            : 'Banned',
    };

    return AdminCard(
      padding: EdgeInsets.zero,
      onTap: () => openAdminUserDetail(context, user.uid),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminAvatar(user: user, size: 58),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            user.name.isEmpty ? 'Unnamed' : user.name,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SoftPill(
                            roleLabel(user.role),
                            color: isAdmin
                                ? AppColors.coralDeep
                                : user.role == UserRole.both
                                ? AppColors.teal
                                : AppColors.gray,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.gray,
                        ),
                      ),
                      if (user.trustedBadge || pending > 0) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (user.trustedBadge)
                              const SoftPill(
                                'Trusted Seller',
                                color: AppColors.teal,
                                icon: Icons.verified_outlined,
                              ),
                            if (pending > 0)
                              SoftPill(
                                'Flagged · $pending pending',
                                color: AppColors.red,
                                icon: Icons.flag_outlined,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isAdmin && user.uid != me)
                  _UserMenu(user: user)
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: banned
                ? AppColors.red.withValues(alpha: 0.07)
                : AppColors.paper,
            child: Row(
              children: [
                if (isAdmin) ...[
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 18,
                    color: AppColors.coralDeep,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Full permissions',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.star_outline_rounded,
                    size: 18,
                    color: banned ? AppColors.red : AppColors.teal,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${user.avgRating.toStringAsFixed(1)} '
                      '(${user.completedTransactions} deal${user.completedTransactions == 1 ? '' : 's'})',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Flexible(
                  child: SoftPill(
                    statusLabel,
                    color: accountStatusColor(user.accountStatus),
                    dot: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final active = user.accountStatus == AccountStatus.active;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.ink),
      color: AppColors.surface,
      onSelected: (v) {
        switch (v) {
          case 'view':
            openAdminUserDetail(context, user.uid);
          case 'suspend':
            setAccountStatusFlow(context, user, AccountStatus.suspended);
          case 'ban':
            setAccountStatusFlow(context, user, AccountStatus.banned);
          case 'reactivate':
            setAccountStatusFlow(context, user, AccountStatus.active);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'view',
          child: _MenuRow(Icons.person_search_outlined, 'View details'),
        ),
        if (active) ...[
          const PopupMenuItem(
            value: 'suspend',
            child: _MenuRow(
              Icons.pause_circle_outline,
              'Suspend user',
              color: AppColors.amber,
            ),
          ),
          const PopupMenuItem(
            value: 'ban',
            child: _MenuRow(Icons.block, 'Ban account', color: AppColors.red),
          ),
        ] else
          const PopupMenuItem(
            value: 'reactivate',
            child: _MenuRow(
              Icons.play_circle_outline,
              'Re-activate',
              color: AppColors.green,
            ),
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color = AppColors.ink});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: color)),
    ],
  );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // 1 2 3 … N style window around the current page.
    final nums = <int?>[];
    for (var i = 0; i < pages; i++) {
      if (i == 0 || i == pages - 1 || (i - page).abs() <= 1) {
        nums.add(i);
      } else if (nums.isNotEmpty && nums.last != null) {
        nums.add(null);
      }
    }
    return AdminCard(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: page == 0 ? null : () => onPage(page - 1),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final n in nums)
                  n == null
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('…'),
                        )
                      : GestureDetector(
                          onTap: () => onPage(n),
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: n == page
                                  ? AppColors.coralDeep
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${n + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: n == page ? Colors.white : AppColors.ink,
                              ),
                            ),
                          ),
                        ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: page >= pages - 1 ? null : () => onPage(page + 1),
          ),
        ],
      ),
    );
  }
}

/// Full-screen admin view of one account: profile, reports filed against
/// them, deal history and moderation actions.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.uid});

  final String uid;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool _busy = false;

  Future<void> _status(UserModel user, AccountStatus status) async {
    setState(() => _busy = true);
    await setAccountStatusFlow(context, user, status);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearFlags(List<ReportModel> pending) async {
    final ok = await confirmAdminAction(
      context,
      title:
          'Dismiss ${pending.length} report${pending.length == 1 ? '' : 's'}?',
      message:
          'The reports are closed as dismissed and the flag is cleared. '
          'The account is not changed.',
      confirmLabel: 'Dismiss',
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final fs = context.read<AdminProvider>().firestore;
      await Future.wait(
        pending.map(
          (r) => fs.updateReportStatus(r.reportId, ReportStatus.dismissed),
        ),
      );
    } catch (e) {
      debugPrint('clearUserFlags: $e');
      if (mounted) showAdminError(context, 'Could not dismiss. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final me = context.watch<AuthProvider>().firebaseUser?.uid;
    final user = a.user(widget.uid);
    final against = a.reports
        .where(
          (r) =>
              r.targetType == ReportTargetType.user && r.targetId == widget.uid,
        )
        .toList();
    final pending = against
        .where((r) => r.status == ReportStatus.pending)
        .toList();
    final txns = a.transactions
        .where((t) => t.buyerId == widget.uid || t.sellerId == widget.uid)
        .toList();
    final canModerate =
        user != null && user.role != UserRole.admin && user.uid != me;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text(
          'User Detail',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: user == null
          ? const Center(
              child: Text(
                'User not found.',
                style: TextStyle(color: AppColors.gray),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SoftPill(
                    'UID: ${user.uid.length > 10 ? user.uid.substring(0, 10) : user.uid}',
                    color: accountStatusColor(user.accountStatus),
                    dot: true,
                  ),
                ),
                const SizedBox(height: 10),
                _profileCard(user, pending.length),
                const SizedBox(height: 22),
                _sectionHeader(
                  Icons.outlined_flag,
                  'Reports Filed Against',
                  pending.isEmpty
                      ? null
                      : SoftPill(
                          '${pending.length} open case${pending.length == 1 ? '' : 's'}',
                          color: AppColors.red,
                        ),
                ),
                const SizedBox(height: 10),
                if (against.isEmpty)
                  const AdminCard(
                    child: Text(
                      'No reports filed against this account.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  ),
                for (final r in against)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ReportTile(report: r),
                  ),
                const SizedBox(height: 14),
                _sectionHeader(
                  Icons.receipt_long_outlined,
                  'Transaction History',
                  Text(
                    '${txns.length} deal${txns.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (txns.isEmpty)
                  const AdminCard(
                    child: Text(
                      'No deals yet.',
                      style: TextStyle(color: AppColors.gray),
                    ),
                  ),
                for (final t in txns.take(15))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TxnRow(txn: t),
                  ),
              ],
            ),
      bottomNavigationBar: !canModerate
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user.accountStatus == AccountStatus.active)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        _status(user, AccountStatus.suspended),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.amber.withValues(
                                  alpha: 0.22,
                                ),
                                foregroundColor: const Color(0xFF7A4A00),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.pause_circle_outline),
                              label: const Text('Suspend User'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _status(user, AccountStatus.banned),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.red,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.block),
                              label: const Text('Ban Account'),
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _status(user, AccountStatus.active),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.green,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(
                            'Re-activate (${user.accountStatus.value})',
                          ),
                        ),
                      ),
                    if (pending.isNotEmpty)
                      TextButton.icon(
                        onPressed: _busy ? null : () => _clearFlags(pending),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.teal,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Dismiss Reports & Clear Flags'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _profileCard(UserModel user, int pending) {
    final region = [
      user.address.city,
      user.address.province,
    ].where((s) => s.isNotEmpty).join(', ');
    return AdminCard(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AdminAvatar(user: user, size: 84, showStatus: pending == 0),
                  if (pending > 0)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.flag,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          user.name.isEmpty ? 'Unnamed' : user.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SoftPill(roleLabel(user.role), color: AppColors.gray),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        SoftPill(
                          '${user.avgRating.toStringAsFixed(1)} · '
                          '${user.completedTransactions} deals',
                          color: const Color(0xFF9A6200),
                          icon: Icons.star_rounded,
                        ),
                        if (pending > 0)
                          SoftPill(
                            'Flagged: $pending Pending',
                            color: AppColors.red,
                            icon: Icons.warning_amber_rounded,
                          ),
                        if (user.trustedBadge)
                          const SoftPill(
                            'Trusted',
                            color: AppColors.teal,
                            icon: Icons.verified_outlined,
                          ),
                        if (user.accountStatus != AccountStatus.active)
                          SoftPill(
                            user.accountStatus == AccountStatus.banned
                                ? 'Banned'
                                : 'Suspended',
                            color: accountStatusColor(user.accountStatus),
                            dot: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                _info(Icons.mail_outline, 'Contact', user.email),
                _info(
                  Icons.calendar_month_outlined,
                  'Member since',
                  user.createdAt == null
                      ? '—'
                      : DateFormat('MMM y').format(user.createdAt!),
                ),
                _info(
                  Icons.location_on_outlined,
                  'Region',
                  region.isEmpty ? '—' : region,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 18, color: AppColors.coralDeep),
        const SizedBox(height: 4),
        CapsLabel(label, color: AppColors.coralDeep),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5),
        ),
      ],
    ),
  );

  Widget _sectionHeader(IconData icon, String title, Widget? trailing) => Row(
    children: [
      Icon(icon, color: AppColors.coralDeep, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      ?trailing,
    ],
  );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final ReportModel report;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final color = reportStatusColor(report.status);
    return AdminCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                AdminStats.shortCode('RP', report.reportId),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              SoftPill(reportStatusLabel(report.status), color: color),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              report.reason.isEmpty ? 'No reason given.' : '“${report.reason}”',
              style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: AppColors.gray),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'By ${a.nameOf(report.reportedBy)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              Text(
                report.createdAt == null
                    ? 'just now'
                    : timeago.format(report.createdAt!),
                style: const TextStyle(fontSize: 12, color: AppColors.gray),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn});

  final TransactionModel txn;

  @override
  Widget build(BuildContext context) {
    final cancelled = txn.status == TransactionStatus.cancelled;
    return AdminCard(
      radius: 18,
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TransactionChatScreen(transactionId: txn.transactionId),
        ),
      ),
      child: Row(
        children: [
          TaggedThumb(url: txn.listingImage, width: 56, height: 56, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SoftPill(
                      typeLabel(txn.type).toUpperCase(),
                      color: typeColor(txn.type),
                      fontSize: 10,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        txn.listingTitle.isEmpty
                            ? txn.orderNumber
                            : txn.listingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      txn.type == ListingType.swap
                          ? 'Item swap'
                          : AppUtils.formatCurrency(txn.amount),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: txn.type == ListingType.swap
                            ? AppColors.teal
                            : AppColors.ink,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '• ${txnStatusLabel(txn.status)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: txnStatusColor(txn.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.gray),
        ],
      ),
    );
  }
}
