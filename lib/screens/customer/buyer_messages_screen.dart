import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/top_app_bar.dart';
import '../shared/deal_threads.dart';

/// "My Messages": every deal chat the user is in — buying AND selling —
/// open deals first. Two equality queries merged client-side (no indexes).
class BuyerMessagesScreen extends StatefulWidget {
  const BuyerMessagesScreen({super.key});

  @override
  State<BuyerMessagesScreen> createState() => _BuyerMessagesScreenState();
}

class _BuyerMessagesScreenState extends State<BuyerMessagesScreen> {
  String? _uid;
  Stream<List<TransactionModel>>? _stream;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().firebaseUser?.uid ?? '';
    if (uid != _uid) {
      _uid = uid;
      _stream = FirestoreService().streamTransactionsForUser(uid);
    }
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: const TopAppBar(title: 'My Messages'),
      body: StreamBuilder<List<TransactionModel>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('MyMessages: ${snap.error}');
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load your conversations. Check your connection '
                  'and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.gray),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return DealThreadList(
            threads: sortThreads(snap.data!),
            myUid: uid,
          );
        },
      ),
    );
  }
}
