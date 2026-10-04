import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/report_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_card_wrapper.dart';
import '../../widgets/listing_widgets.dart';
import '../../widgets/top_app_bar.dart';
import '../../widgets/type_badge.dart';
import '../customer/listing_detail_screen.dart';
import 'admin_gate.dart';

/// Pending user/listing reports, oldest first (Phase 4.6).
///
/// Every action updates BOTH the report record and its real target.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _firestore = FirestoreService();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: TopAppBar(
          title: 'Report Queue',
          bottom: TabBar(
            controller: _tabs,
            labelColor: AppColors.coral,
            unselectedLabelColor: AppColors.gray,
            indicatorColor: AppColors.coral,
            tabs: const [
              Tab(text: 'Reported Users'),
              Tab(text: 'Reported Listings'),
            ],
          ),
        ),
        body: StreamBuilder<List<ReportModel>>(
          stream:
              _firestore.streamReportsByStatus(ReportStatus.pending),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final pending = snap.data ?? const <ReportModel>[];
            return TabBarView(
              controller: _tabs,
              children: [
                _ReportList(
                  reports: pending
                      .where((r) =>
                          r.targetType == ReportTargetType.user)
                      .toList(),
                  kind: ReportTargetType.user,
                ),
                _ReportList(
                  reports: pending
                      .where((r) =>
                          r.targetType == ReportTargetType.listing)
                      .toList(),
                  kind: ReportTargetType.listing,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.reports, required this.kind});

  final List<ReportModel> reports;
  final ReportTargetType kind;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          kind == ReportTargetType.user
              ? 'No pending user reports.'
              : 'No pending listing reports.',
          style: const TextStyle(color: AppColors.gray),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ReportCard(report: reports[i]),
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  const _ReportCard({required this.report});

  final ReportModel report;

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final _firestore = FirestoreService();
  bool _busy = false;

  ReportModel get _report => widget.report;

  Future<void> _resolve(ReportStatus status) async {
    setState(() => _busy = true);
    try {
      await _firestore.updateReportStatus(_report.reportId, status);
    } catch (e) {
      debugPrint('resolveReport: $e');
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

  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'warn':
          await _firestore.updateReportStatus(
            _report.reportId,
            ReportStatus.warned,
          );
          await _firestore.addNotification(
            _report.targetId,
            const NotificationModel(
              type: NotificationType.system,
              message:
                  'An admin reviewed reports about your account. Please keep listings honest and respectful.',
              relatedId: '',
            ),
          );
        case 'suspend':
          await _firestore.updateAccountStatus(
            _report.targetId,
            AccountStatus.suspended,
          );
          await _firestore.updateReportStatus(
            _report.reportId,
            ReportStatus.suspended,
          );
        case 'remove':
          await _firestore.updateListing(
            _report.targetId,
            {'status': ListingStatus.removed.value},
          );
          await _firestore.updateReportStatus(
            _report.reportId,
            ReportStatus.removed,
          );
      }
    } catch (e) {
      debugPrint('reportAction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action failed. Try again.'),
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
    final isUser = _report.targetType == ReportTargetType.user;
    return AppCardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _report.reason.isEmpty
                      ? 'No reason given'
                      : '"${_report.reason}"',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              Text(
                _report.createdAt == null
                    ? ''
                    : AppUtils.formatDate(_report.createdAt),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.gray),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _targetPreview(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: UserNameText(
                  _report.reportedBy,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.gray),
                ),
              ),
              FutureBuilder<List<ReportModel>>(
                future: _firestore.reportsForTarget(_report.targetId),
                builder: (context, snap) {
                  final strikes = (snap.data ?? const <ReportModel>[])
                      .where((r) => r.status != ReportStatus.pending)
                      .length;
                  return Text(
                    strikes == 0
                        ? 'first report'
                        : '$strikes prior action${strikes == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _resolve(ReportStatus.dismissed),
                child: const Text('Dismiss'),
              ),
              if (isUser) ...[
                OutlinedButton(
                  onPressed: _busy ? null : () => _act('warn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.amber,
                    side: const BorderSide(color: AppColors.amber),
                  ),
                  child: const Text('Warn User'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _act('suspend'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  child: const Text('Suspend Account'),
                ),
              ] else
                FilledButton(
                  onPressed: _busy ? null : () => _act('remove'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  child: const Text('Remove Listing'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Live preview of the reported target.
  Widget _targetPreview() {
    if (_report.targetType == ReportTargetType.user) {
      return UserLookup(
        uid: _report.targetId,
        builder: (context, user) => Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.cream,
              backgroundImage: (user?.photoUrl.isNotEmpty ?? false)
                  ? NetworkImage(user!.photoUrl)
                  : null,
              child: (user?.photoUrl.isNotEmpty ?? false)
                  ? null
                  : const Icon(Icons.person_outline,
                      color: AppColors.gray, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: UserNameText(
                _report.targetId,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return FutureBuilder<ListingModel?>(
      future: _firestore.getListing(_report.targetId),
      builder: (context, snap) {
        final l = snap.data;
        if (l == null) {
          return const Text(
            'Listing unavailable (maybe removed).',
            style: TextStyle(fontSize: 13, color: AppColors.gray),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: l.listingId),
            ),
          ),
          child: Row(
            children: [
              ListingThumb(
                url: l.images.isNotEmpty ? l.images.first : '',
                size: 44,
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
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    TypeBadge(l.type),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.gray),
            ],
          ),
        );
      },
    );
  }
}
