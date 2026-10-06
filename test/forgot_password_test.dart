// Forgot password: the dialog must close cleanly (its controller used to be
// disposed while the dialog was still animating out → crash) and send the
// reset email for the typed address. Firebase-free: AuthService is faked.

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:swidshop/providers/auth_provider.dart';
import 'package:swidshop/screens/auth/login_screen.dart';
import 'package:swidshop/services/auth_service.dart';
import 'package:swidshop/services/firestore_service.dart';

class _FakeAuth implements AuthService {
  final sentTo = <String>[];

  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  Future<void> sendPasswordReset(String email) async => sentTo.add(email);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirestore implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_FakeAuth> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final auth = _FakeAuth();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) =>
            AuthProvider(authService: auth, firestoreService: _FakeFirestore()),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    return auth;
  }

  testWidgets('sends the reset link and closes without errors', (
    tester,
  ) async {
    final auth = await pumpLogin(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '  mel@example.com ',
    );
    await tester.tap(find.text('Send link'));
    // Let the dialog's close animation run fully (the old crash point).
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reset password'), findsNothing);
    expect(auth.sentTo, ['mel@example.com']);
    expect(find.textContaining('reset link is on its way'), findsOneWidget);
  });

  testWidgets('bad email is caught in the dialog, nothing sent', (
    tester,
  ) async {
    final auth = await pumpLogin(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'not-an-email',
    );
    await tester.tap(find.text('Send link'));
    await tester.pump();
    expect(find.text('That email address is not valid.'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(auth.sentTo, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(auth.sentTo, isEmpty);
  });
}
