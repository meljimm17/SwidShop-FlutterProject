import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:swidshop/models/chat_message_model.dart';
import 'package:swidshop/models/transaction_model.dart';
import 'package:swidshop/providers/auth_provider.dart';
import 'package:swidshop/screens/shared/transaction_chat_screen.dart';
import 'package:swidshop/services/auth_service.dart';
import 'package:swidshop/services/firestore_service.dart';

class _FakeAuthService implements AuthService {
  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthFirestore implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineChatFirestore extends _FakeAuthFirestore {
  @override
  Stream<TransactionModel?> streamTransaction(String transactionId) =>
      Stream.value(null);

  @override
  Stream<List<ChatMessageModel>> streamMessages(String transactionId) =>
      Stream.error(StateError('offline'));
}

void main() {
  testWidgets('chat stream errors are not shown as an empty conversation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(
          authService: _FakeAuthService(),
          firestoreService: _FakeAuthFirestore(),
        ),
        child: MaterialApp(
          home: TransactionChatScreen(
            transactionId: 'deal-1',
            firestoreService: _OfflineChatFirestore(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't load messages."), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Start the conversation'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't load messages."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
