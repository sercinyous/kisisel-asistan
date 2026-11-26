import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/auth/data/google_identity_client.dart';
import 'package:kisisel_asistan/features/auth/data/sign_in_backend.dart';
import 'package:kisisel_asistan/features/auth/domain/sign_in_messages.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_controller.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Google implements GoogleIdentityClient {
  int calls = 0;

  @override
  Future<GoogleIdentity> signIn() async {
    calls++;
    return const GoogleIdentity(idToken: 't', email: 'kisi@gmail.com');
  }
}

class _Backend implements SignInBackend {

  final List<String> resetRequests = [];

  @override
  Future<void> sendPasswordReset({required String email}) async {
    resetRequests.add(email);
    if (error != null) throw error!;
  }

  @override
  Future<void> verifyResetCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<void> setNewPassword(String newPassword) async {}

  @override
  bool get hasSession => false;
  Object? error;
  int googleCalls = 0;
  int passwordCalls = 0;
  int signUpCalls = 0;

  @override
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    signUpCalls++;
    if (error != null) throw error!;
    return false;
  }

  @override
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    googleCalls++;
    if (error != null) throw error!;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    passwordCalls++;
    if (error != null) throw error!;
  }
}

void main() {
  late _Google google;
  late _Backend backend;

  setUp(() {
    google = _Google();
    backend = _Backend();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool googleAvailable,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googleLoginAvailableProvider.overrideWithValue(googleAvailable),
          googleIdentityClientProvider.overrideWithValue(google),
          signInBackendProvider.overrideWithValue(backend),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
  }

  testWidgets('Google açıkken ana düğme Google, e-posta ikincil ve gizli form',
      (tester) async {
    await pumpScreen(tester, googleAvailable: true);

    expect(find.text('Google ile devam et'), findsOneWidget);
    expect(find.text('E-posta ile giriş'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.byKey(const Key('sign-in-email-toggle')));
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('E-posta ile giriş'), findsNothing);
    expect(find.text('Google ile devam et'), findsOneWidget);
  });

  testWidgets('Google yapılandırılmamışsa (ya da web demosunda) yalnızca form',
      (tester) async {
    await pumpScreen(tester, googleAvailable: false);

    expect(find.text('Google ile devam et'), findsNothing);
    expect(find.byKey(const Key('sign-in-google')), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Giriş yap'), findsOneWidget);
  });

  testWidgets('Google düğmesi girişi başlatır', (tester) async {
    await pumpScreen(tester, googleAvailable: true);

    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();

    expect(google.calls, 1);
    expect(backend.googleCalls, 1);
    expect(find.byKey(const Key('sign-in-error')), findsNothing);
  });

  testWidgets('hesap kaydedilemezse anlaşılır Türkçe mesaj görünür',
      (tester) async {
    backend.error = const AuthApiException(
      'Database error saving new user',
      statusCode: '500',
      code: 'unexpected_failure',
    );
    await pumpScreen(tester, googleAvailable: true);

    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();

    expect(find.text(signUpFailedMessage), findsOneWidget);
  });

  testWidgets('e-posta formu doğrulanır ve gönderilir', (tester) async {
    await pumpScreen(tester, googleAvailable: false);

    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump();
    expect(find.text('Geçerli bir e-posta gir.'), findsOneWidget);
    expect(backend.passwordCalls, 0);

    await tester.enterText(find.byType(TextFormField).first, 'ben@gmail.com');
    await tester.enterText(find.byType(TextFormField).last, 'sifre');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(backend.passwordCalls, 1);
  });

  testWidgets('Kayıt ol geçişi hesap oluşturur ve onay bilgisini gösterir',
      (tester) async {
    await pumpScreen(tester, googleAvailable: false);

    expect(find.textContaining('davet'), findsNothing);
    await tester.tap(find.byKey(const Key('sign-in-mode-toggle')));
    await tester.pump();
    expect(find.text('Hesap oluştur'), findsOneWidget);
    expect(find.text('Hesabın var mı? Giriş yap'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'yeni@gmail.com');
    await tester.enterText(find.byType(TextFormField).last, '123');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump();
    expect(find.text('Şifre en az 8 karakter olmalı.'), findsOneWidget);
    expect(backend.signUpCalls, 0);

    await tester.enterText(find.byType(TextFormField).last, 'sifre123');
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(backend.signUpCalls, 1);
    expect(backend.passwordCalls, 0);
    expect(find.text(confirmationSentMessage), findsOneWidget);
  });
}
