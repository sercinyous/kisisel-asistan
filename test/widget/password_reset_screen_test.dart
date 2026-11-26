import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/auth/data/sign_in_backend.dart';
import 'package:kisisel_asistan/features/auth/presentation/password_reset_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Backend implements SignInBackend {
  final List<String> requests = [];
  final List<(String, String, String)> resets = [];
  Object? sendError;

  @override
  Future<void> sendPasswordReset({required String email}) async {
    requests.add(email);
    if (sendError != null) throw sendError!;
  }

  final List<(String, String)> verified = [];
  Object? passwordErrorOnce;
  bool session = false;

  @override
  Future<void> verifyResetCode({
    required String email,
    required String code,
  }) async {
    verified.add((email, code));
    session = true;
  }

  @override
  Future<void> setNewPassword(String newPassword) async {
    final error = passwordErrorOnce;
    passwordErrorOnce = null;
    if (error != null) throw error;
    final (email, code) = verified.last;
    resets.add((email, code, newPassword));
  }

  @override
  bool get hasSession => session;

  @override
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {}

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async =>
      false;
}

void main() {
  Future<_Backend> pump(WidgetTester tester) async {
    final backend = _Backend();
    await tester.pumpWidget(ProviderScope(
      overrides: [signInBackendProvider.overrideWithValue(backend)],
      child: const MaterialApp(
        home: PasswordResetScreen(initialEmail: 'kisi@example.com'),
      ),
    ));
    return backend;
  }

  testWidgets('kod gönderilir, kod + yeni şifre ile sıfırlanır',
      (tester) async {
    final backend = await pump(tester);
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(backend.requests, ['kisi@example.com']);
    expect(find.text(resetCodeSentMessage), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reset-code')), '123456');
    await tester.enterText(
        find.byKey(const Key('reset-password')), 'yeniSifre1');
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(backend.resets, [('kisi@example.com', '123456', 'yeniSifre1')]);
  });

  testWidgets('kayıtsız adres de aynı bilgiyi görür (varlık sızmaz)',
      (tester) async {
    final backend = await pump(tester);
    backend.sendError = const AuthException('User not found');
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(find.text(resetCodeSentMessage), findsOneWidget);
    expect(find.byKey(const Key('reset-error')), findsNothing);
  });

  testWidgets('şifre reddedilirse tekrar denemede kod yeniden doğrulanmaz',
      (tester) async {
    final backend = await pump(tester);
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    backend.passwordErrorOnce = const AuthException('network');
    await tester.enterText(find.byKey(const Key('reset-code')), '123456');
    await tester.enterText(
        find.byKey(const Key('reset-password')), 'yeniSifre1');
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(backend.resets, isEmpty);
    expect(backend.verified.length, 1);

    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(backend.verified.length, 1);
    expect(backend.resets, [('kisi@example.com', '123456', 'yeniSifre1')]);
  });
}
