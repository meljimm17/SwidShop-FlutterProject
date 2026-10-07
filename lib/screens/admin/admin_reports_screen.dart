import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/report_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../customer/listing_detail_screen.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

enum _StatusView { pendingFirst, pending, resolved }

/// Reports tab: live triage queue for user and listing reports (Phase 4.6).
///
/// Every action updates the report AND its real target (account status,
/// listing status, or a warning notification).
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  ReportTargetType _kind = ReportTargetType.user;
  _StatusView _view = _StatusView.pendingFirst;
  bool _newestFirst = false;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    List<ReportModel> of(ReportTargetType k) =>
        a.reports.where((r) => r.targetType == k).toList();
    final users = of(ReportTargetType.user);
    final listings = of(ReportTargetType.listing);
    int pendingIn(List<ReportModel> rs) =>
        rs.where((r) => r.status == ReportStatus.pending).length;

    final base = _kind == ReportTargetType.user ? users : listings;
    var list = switch (_view) {
      _StatusView.pending =>
        base.where((r) => r.status == ReportStatus.pending).toList(),
      _StatusView.resolved =>
        base.where((r) => r.status != ReportStatus.pending).toList(),
      _StatusView.pendingFirst => base.toList(),
    };
    int byDate(ReportModel x, ReportModel y) {
      final ax = x.createdAt ?? DateTime.now();
      final ay = y.createdAt ?? DateTime.now();
      return _newestFirst ? ay.compareTo(ax) : ax.compareTo(ay);
    }

    list.sort((x, y) {
      if (_view == _StatusView.pendingFirst) {
        final px = x.status == ReportStatus.pending ? 0 : 1;
        final py = y.status == ReportStatus.pending ? 0 : 1;
        if (px != py) return px.compareTo(py);
      }
      return byDate(x, y);
    });

    // Targets with 3+ open reports at once — escalate.
    final openByTarget = <String, int>{};
    for (final r in base.where((r) => r.status == ReportStatus.pending)) {
      openByTarget[r.targetId] = (openByTarget[r.targetId] ?? 0) + 1;
    }
    final escalated = openByTarget.values.where((n) => n >= 3).length;
    final resolved = base.where((r) => r.status != ReportStatus.pending).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live Triage Queue',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              SoftPill(
                '${a.pendingQueueCount} open',
                color: AppColors.ink,
                icon: Icons.shield_outlined,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                _segment(
                  ReportTargetType.user,
                  Icons.person_outline,
                  'Reported Users (${pendingIn(users)})',
                ),
                _segment(
                  ReportTargetType.listing,
                  Icons.storefront_outlined,
                  'Reported Listings (${pendingIn(listings)})',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        PillRow<_StatusView>(
          compact: true,
          selected: _view,
          onSelected: (v) => setState(() => _view = v),
          options: const [
            PillOption(
              _StatusView.pendingFirst,
              'Pending first',
              icon: Icons.assignment_outlined,
            ),
            PillOption(_StatusView.pending, 'Open only'),
            PillOption(_StatusView.resolved, 'Resolved'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink),
              icon: const Icon(Icons.swap_vert, size: 18),
              label: Text(
                _newestFirst ? 'Sort: Newest first' : 'Sort: Oldest first',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        if (escalated > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFF9A6200),
                  child: Icon(Icons.priority_high, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Escalation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7A4A00),
                        ),
                      ),
                      Text(
                        '$escalated ${_kind == ReportTargetType.user ? 'account' : 'listing'}'
                        '${escalated == 1 ? ' has' : 's have'} 3+ open reports',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF7A4A00),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _view == _StatusView.resolved
                    ? 'Nothing resolved yet.'
                    : 'Queue is clear — no reports here.',
                style: const TextStyle(color: AppColors.gray),
              ),
            ),
          ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _ReportCard(key: ValueKey(r.reportId), report: r),
          ),
        if (base.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: AdminCard(
              color: AppColors.mist,
              radius: 999,
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFFBDEFD9),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resolution rate ${(resolved / base.length * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$resolved resolved · ${base.length - resolved} open '
                          'of ${base.length} ${_kind == ReportTargetType.user ? 'user' : 'listing'} reports',
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
          ),
      ],
    );
  }

  Widget _segment(ReportTargetType kind, IconData icon, String label) {
    final on = _kind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _kind = kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: on ? AppColors.coralDeep : AppColors.gray,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: on ? AppColors.coralDeep : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  const _ReportCard({super.key, required this.report});

  final ReportModel report;

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  ReportModel get _r => widget.report;

  Future<void> _act(String action) async {
    final a = context.read<AdminProvider>();
    final fs = a.firestore;
    final isUser = _r.targetType == ReportTargetType.user;
    final listing = isUser ? null : a.listing(_r.targetId);
    final targetName = isUser
        ? a.nameOf(_r.targetId)
        : (listing?.title ?? 'this listing');

    if (action != 'dismiss') {
      final ok = await confirmAdminAction(
        context,
        title: switch (action) {
          'warn' => isUser ? 'Warn $targetName?' : 'Warn the seller?',
          'suspend' => 'Suspend $targetName?',
          _ => 'Remove "$targetName"?',
        },
        message: switch (action) {
          'warn' =>
            'They get an in-app warning and the report is closed as warned.',
          'suspend' =>
            'The account is signed out and blocked until re-activated.',
          _ => 'The listing disappears from every feed immediately.',
        },
        confirmLabel: switch (action) {
          'warn' => 'Send warning',
          'suspend' => 'Suspend',
          _ => 'Remove',
        },
        destructive: action != 'warn',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      switch (action) {
        case 'dismiss':
          await fs.updateReportStatus(_r.reportId, ReportStatus.dismissed);
        case 'warn':
          final recipient = isUser ? _r.targetId : (listing?.sellerId ?? '');
          if (recipient.isNotEmpty) {
            await fs.addNotification(
              recipient,
              NotificationModel(
                type: NotificationType.system,
                message: isUser
                    ? 'An admin reviewed reports about your account. Please '
                          'keep listings honest and deals respectful.'
                    : 'An admin reviewed a report on "${listing?.title ?? 'your listing'}". '
                          'Please make sure it is accurate and allowed.',
                relatedId: isUser ? '' : 'listing:${_r.targetId}',
              ),
            );
          }
          await fs.updateReportStatus(_r.reportId, ReportStatus.warned);
        case 'suspend':
          await fs.updateAccountStatus(_r.targetId, AccountStatus.suspended);
          await fs.updateReportStatus(_r.reportId, ReportStatus.suspended);
        case 'remove':
          await fs.updateListing(
            _r.targetId,
            {'status': ListingStatus.removed.value},
            auditAdminAction: true,
          );
          await fs.updateReportStatus(_r.reportId, ReportStatus.removed);
      }
    } catch (e) {
      debugPrint('reportAction: $e');
      if (mounted) showAdminError(context, 'Action failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AdminProvider>();
    final pending = _r.status == ReportStatus.pending;
    final color = pending
        ? (_r.createdAt != null &&
                  DateTime.now().difference(_r.createdAt!).inHours >= 24
              ? AppColors.red
              : AppColors.amber)
        : AppColors.teal;
    final reporter = a.user(_r.reportedBy);
    final isUser = _r.targetType == ReportTargetType.user;

    return Container(
      decoration: BoxDecoration(
        color: pending ? AppColors.surface : AppColors.mist,
        borderRadius: BorderRadius.circular(22),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminAvatar(user: reporter, size: 38, showStatus: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reported by ${a.nameOf(_r.reportedBy)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_r.createdAt == null ? 'just now' : timeago.format(_r.createdAt!)}'
                      ' • Case ${AdminStats.shortCode('REP', _r.reportId)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              SoftPill(
                pending ? 'Pending' : 'Resolved',
                color: pending ? const Color(0xFF9A6200) : AppColors.teal,
                icon: pending
                    ? Icons.hourglass_top
                    : Icons.check_circle_outline,
                solid: pending,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isUser) _userTarget(a) else _listingTarget(a),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: pending ? AppColors.coralDeep : AppColors.gray,
              ),
              const SizedBox(width: 6),
              CapsLabel(
                isUser ? 'User report' : 'Listing report',
                color: pending ? AppColors.coralDeep : AppColors.gray,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _r.reason.isEmpty ? 'No reason given.' : '“${_r.reason}”',
            style: const TextStyle(fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (pending)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  'Dismiss',
                  AppColors.mist,
                  AppColors.ink,
                  () => _act('dismiss'),
                ),
                _actionButton(
                  isUser ? 'Warn User' : 'Warn Seller',
                  AppColors.amber.withValues(alpha: 0.25),
                  const Color(0xFF7A4A00),
                  () => _act('warn'),
                ),
                if (isUser)
                  _actionButton(
                    'Suspend Account',
                    const Color(0xFF8A5200),
                    Colors.white,
                    () => _act('suspend'),
                  )
                else
                  _actionButton(
                    'Remove Listing',
                    AppColors.red,
                    Colors.white,
                    () => _act('remove'),
                  ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Resolved as ${reportStatusLabel(_r.status).toLowerCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color bg, Color fg, VoidCallback onTap) {
    return FilledButton(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _userTarget(AdminProvider a) {
    final u = a.user(_r.targetId);
    final strikes = AdminStats.strikesFor(a.reports, _r.targetId);
    return InkWell(
      onTap: () => openAdminUserDetail(context, _r.targetId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AdminAvatar(user: u, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.nameOf(_r.targetId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (u != null)
                    Text(
                      [
                        if (u.createdAt != null)
                          'Member since ${DateFormat('MMM y').format(u.createdAt!)}',
                        if (u.address.city.isNotEmpty) u.address.city,
                      ].join(' • '),
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
            const SizedBox(width: 6),
            SoftPill(
              strikes == 0
                  ? 'No prior strikes'
                  : '$strikes prev strike${strikes == 1 ? '' : 's'}',
              color: strikes == 0 ? AppColors.gray : AppColors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _listingTarget(AdminProvider a) {
    final l = a.listing(_r.targetId);
    if (l == null) {
      return const Text(
        'Listing unavailable (deleted).',
        style: TextStyle(fontSize: 13, color: AppColors.gray),
      );
    }
    final strikes = AdminStats.strikesFor(a.reports, l.sellerId);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: l.listingId),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            TaggedThumb(
              url: l.images.isNotEmpty ? l.images.first : '',
              width: 56,
              height: 56,
              radius: 10,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${a.nameOf(l.sellerId)}'
                    '${strikes > 0 ? ' • $strikes seller strike${strikes == 1 ? '' : 's'}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      SoftPill(
                        l.displayPrice == null
                            ? typeLabel(l.type)
                            : '${typeLabel(l.type)} ${AppUtils.formatCurrency(l.displayPrice)}',
                        color: typeColor(l.type),
                        fontSize: 10.5,
                      ),
                      if (l.status == ListingStatus.removed)
                        const SoftPill(
                          'Removed',
                          color: AppColors.red,
                          fontSize: 10.5,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.gray),
          ],
        ),
      ),
    );
  }
}
