import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/payment_model.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/top_app_bar.dart';

/// Reusable SIMULATED GCash screen (Step 1 — demo mode, NO real money).
///
/// Shows the item + amount, plays a short loading step during which
/// [apply] saves the `payments` record and applies the purchase (one
/// batch), then a "Payment Successful" pop-up with the reference number.
/// If [apply] fails nothing is shown as paid and the user can retry.
/// Returns the reference via `Navigator.pop(ref)`; null when cancelled.
class DemoGcashScreen extends StatefulWidget {
  const DemoGcashScreen({
    super.key,
    required this.itemLabel,
    required this.amount,
    required this.apply,
  });

  final String itemLabel;
  final double amount;

  /// Records the payment + applies the item for reference `ref`.
  final Future<void> Function(String ref) apply;

  @override
  State<DemoGcashScreen> createState() => _DemoGcashScreenState();
}

class _DemoGcashScreenState extends State<DemoGcashScreen> {
  bool _paying = false;

  Future<void> _pay() async {
    setState(() => _paying = true);
    final ref = PaymentModel.newReference();
    try {
      // Simulated provider round-trip, then record + apply atomically.
      await Future.delayed(const Duration(milliseconds: 1500));
      await widget.apply(ref);
    } catch (e) {
      debugPrint('demoPayment.apply: $e');
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Payment failed — nothing was charged. Please try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _paying = false);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.green,
              size: 64,
            ),
            const SizedBox(height: 12),
            const Text(
              'Payment Successful',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.itemLabel}\n${AppUtils.formatCurrency(widget.amount)}\nRef: $ref',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_paying,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: TopAppBar(
        title: 'GCash',
        // No backing out half-way through a payment.
        showBack: !_paying,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF007DFF),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              ),
              child: const Column(
                children: [
                  Text(
                    'GCash',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Pay SwidShop securely',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _kv('Item', widget.itemLabel),
            const SizedBox(height: 8),
            _kv('Amount', AppUtils.formatCurrency(widget.amount)),
            const Spacer(),
            PrimaryButton(
              label: 'Pay ${AppUtils.formatCurrency(widget.amount)}',
              loading: _paying,
              onPressed: _paying ? null : _pay,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        Text(k, style: const TextStyle(color: AppColors.gray)),
        const Spacer(),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Pushes the demo flow; [apply] runs on "payment" (see
/// [DemoGcashScreen]). Returns the reference, or null when cancelled.
Future<String?> runDemoPayment(
  BuildContext context, {
  required String itemLabel,
  required double amount,
  required Future<void> Function(String ref) apply,
}) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DemoGcashScreen(
          itemLabel: itemLabel,
          amount: amount,
          apply: apply,
        ),
      ),
    );
