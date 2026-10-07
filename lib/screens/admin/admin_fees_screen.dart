import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/payment_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/top_app_bar.dart';
import 'admin_gate.dart';
import 'admin_widgets.dart';

/// Pushes the Fees page, carrying the shell's [AdminProvider] into the new
/// route (pushed routes do not inherit providers placed inside the shell).
void openAdminFees(BuildContext context) {
  final admin = context.read<AdminProvider>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: admin,
        child: const AdminFeesScreen(),
      ),
    ),
  );
}

/// Payment ledger (simulated): recent payments and outstanding platform fees.
class AdminFeesScreen extends StatefulWidget {
  const AdminFeesScreen({super.key});

  @override
  State<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends State<AdminFeesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final txns = admin.transactions
        .where((t) => t.feeStatus != 'none')
        .toList();
    final open = txns
        .where((t) => t.feeUnpaid && t.status != TransactionStatus.cancelled)
        .toList();
    final unpaid = open.where((t) => !t.feeOverdue).toList();
    final overdue = open.where((t) => t.feeOverdue).toList();
    final paid = txns.where((t) => t.feeStatus == 'paid').toList();
    final payments = admin.payments;
    return AdminGate(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: TopAppBar(
          title: 'Fees',
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: AppColors.coralDeep,
            unselectedLabelColor: AppColors.gray,
            indicatorColor: AppColors.coralDeep,
            tabs: [
              Tab(text: 'Recent Payments (${payments.length})'),
              Tab(text: 'Unpaid (${unpaid.length})'),
              Tab(text: 'Overdue (${overdue.length})'),
              Tab(text: 'Paid (${paid.length})'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _PaymentList(payments: payments),
            _FeeList(txns: unpaid, empty: 'No unpaid fees.'),
            _FeeList(txns: overdue, empty: 'Nothing overdue.'),
            _FeeList(txns: paid, empty: 'No paid fees yet.'),
          ],
        ),
      ),
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.payments});

  final List<PaymentModel> payments;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    if (payments.isEmpty) {
      return Center(
        child: Text(
          admin.paymentsError == null
              ? 'No payments yet.'
              : 'Payments could not be loaded. Check your connection and '
                    'try again later.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.gray),
        ),
      );
    }
    return Column(
      children: [
        if (admin.paymentsError != null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Payment updates are unavailable. The list may be out of date.',
              style: TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index];
              final type = RevenueStats.labels[payment.type] ?? payment.type;
              final label = payment.label.isEmpty ? type : payment.label;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AdminCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 19,
                        backgroundColor: AppColors.mist,
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 19,
                          color: AppColors.teal,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${admin.nameOf(payment.userId)} · $type',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                              ),
                            ),
                            if (payment.referenceNo.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Ref ${payment.referenceNo}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.gray,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Text(
                              AppUtils.formatDateTime(payment.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.gray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppUtils.formatCurrency(payment.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeeList extends StatelessWidget {
  const _FeeList({required this.txns, required this.empty});

  final List<TransactionModel> txns;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) {
      return Center(
        child: Text(empty, style: const TextStyle(color: AppColors.gray)),
      );
    }
    // Group by seller for per-account hold/lift.
    final bySeller = <String, List<TransactionModel>>{};
    for (final t in txns) {
      (bySeller[t.sellerId] ??= []).add(t);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bySeller.length,
      itemBuilder: (context, i) {
        final entry = bySeller.entries.elementAt(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SellerFeeCard(sellerId: entry.key, txns: entry.value),
        );
      },
    );
  }
}

class _SellerFeeCard extends StatefulWidget {
  const _SellerFeeCard({required this.sellerId, required this.txns});

  final String sellerId;
  final List<TransactionModel> txns;

  @override
  State<_SellerFeeCard> createState() => _SellerFeeCardState();
}

class _SellerFeeCardState extends State<_SellerFeeCard> {
  bool _busy = false;

  Future<void> _hold(bool hold) async {
    final admin = context.read<AdminProvider>();
    final name = admin.nameOf(widget.sellerId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(hold ? 'Hold $name?' : 'Lift hold on $name?'),
        content: Text(
          hold
              ? 'Their listings are hidden and they cannot post or accept '
                    'swaps. They can still log in, chat and pay. A manual hold '
                    'stays until an admin lifts it, even after paying.'
              : 'Their listings become visible again. If they still have '
                    'overdue fees, the automatic hold returns at the next check.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(hold ? 'Hold' : 'Lift'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await admin.firestore.adminSetFeeHold(widget.sellerId, hold: hold);
    } catch (e) {
      debugPrint('manualHold: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message : 'Could not update. Try again.',
            ),
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
    final admin = context.watch<AdminProvider>();
    final seller = admin.user(widget.sellerId);
    var total = 0.0;
    for (final t in widget.txns) {
      total += t.feeAmount;
    }
    final onHold = seller?.accountStatus == AccountStatus.onHold;
    // A fee hold must never replace a suspension or ban.
    final blocked =
        seller?.accountStatus == AccountStatus.suspended ||
        seller?.accountStatus == AccountStatus.banned;
    final hasOutstandingFee = widget.txns.any(
      (t) => t.feeUnpaid && t.status != TransactionStatus.cancelled,
    );
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(user: seller, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  admin.nameOf(widget.sellerId),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (onHold)
                SoftPill(
                  seller!.holdManual ? 'On hold (admin)' : 'On hold',
                  color: AppColors.red,
                ),
              if (blocked)
                SoftPill(
                  accountStatusLabel(seller!.accountStatus),
                  color: accountStatusColor(seller.accountStatus),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in widget.txns)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
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
                  Text(
                    '${AppUtils.formatCurrency(t.feeAmount)} · ${t.feeStatus}',
                    style: const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total ${AppUtils.formatCurrency(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (onHold || (hasOutstandingFee && !blocked))
                TextButton(
                  onPressed: _busy || blocked || seller == null
                      ? null
                      : () => _hold(!onHold),
                  child: Text(onHold ? 'Lift hold' : 'Hold account'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
