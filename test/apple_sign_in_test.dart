import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/apple_auth.dart';
import 'package:kisisel_asistan/features/auth/data/sign_in_backend.dart';
import 'package:kisisel_asistan/features/auth/domain/sign_in_messages.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_controller.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_screen.dart';
import 'package:kisisel_asistan/features/settings/data/account_repository.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'sign_in_controller_test.dart'
    show FakeGoogleIdentityClient, FakeSignInBackend;

class FakeAppleClient implements AppleIdentityClient {
  FakeAppleClient({this.error, this.code = 'yetki-kodu'});

  Object? error;
  String? code;
  int calls = 0;

  @override
  Future<AppleCredential> signIn() async {
    calls++;
    if (error != null) throw error!;
    return AppleCredential(
      idToken: 'apple-id-token',
      rawNonce: 'ham-nonce',
      authorizationCode: code,
      givenName: 'Ayşe',
      familyName: 'Yılmaz',
    );
  }
}

void main() {
  group('nonce', () {
    test('ham nonce istenen uzunlukta ve güvenli karakterlerden', () {
      final nonce = generateRawNonce();
      expect(nonce.length, 32);
      expect(RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(nonce), isTrue);
      expect(generateRawNonce(), isNot(nonce));
      expect(generateRawNonce(16, Random(1)), generateRawNonce(16, Random(1)));
    });

    test('Apple\'a giden değer ham nonce\'un SHA-256 özeti', () {
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('AppleCredential', () {
    test('tam ad ilk yetkilendirmedeki parçalardan', () {
      const full = AppleCredential(
          idToken: 't',
          rawNonce: 'n',
          givenName: ' Ayşe ',
          familyName: 'Yılmaz');
      expect(full.fullName, 'Ayşe Yılmaz');
      const none = AppleCredential(idToken: 't', rawNonce: 'n', givenName: '');
      expect(none.fullName, isNull);
    });
  });

  group('hata çevirisi', () {
    test('vazgeçme sessiz, diğerleri Türkçe metin', () {
      final canceled = translateAppleSignInError(
        const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled, message: 'x'),
      );
      expect(canceled.kind, AppleAuthErrorKind.canceled);
      expect(signInErrorMessage(canceled), isNull);

      final failed = translateAppleSignInError(
        const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed, message: 'x'),
      );
      expect(signInErrorMessage(failed),
          'Apple ile giriş yapılamadı. Tekrar dene.');

      final unsupported = translateAppleSignInError(
          const SignInWithAppleNotSupportedException(message: 'x'));
      expect(unsupported.kind, AppleAuthErrorKind.unavailable);
      expect(translateAppleSignInError(StateError('x')).kind,
          AppleAuthErrorKind.unknown);
    });
  });

  group('denetleyici', () {
    late FakeSignInBackend backend;
    late FakeAppleClient apple;
    late ProviderContainer container;

    setUp(() {
      backend = FakeSignInBackend();
      apple = FakeAppleClient();
      container = ProviderContainer(overrides: [
        appleIdentityClientProvider.overrideWith((ref) => apple),
        signInBackendProvider.overrideWithValue(backend),
      ]);
      addTearDown(container.dispose);
    });

    test('belirteç, ham nonce ve ad Supabase girişine verilir', () async {
      final ok = await container
          .read(signInControllerProvider.notifier)
          .signInWithApple();
      expect(ok, isTrue);
      expect(backend.appleCalls.single, (
        idToken: 'apple-id-token',
        rawNonce: 'ham-nonce',
        fullName: 'Ayşe Yılmaz',
      ));
      expect(container.read(signInControllerProvider).error, isNull);
    });

    test('vazgeçmede hata gösterilmez, giriş yapılmaz', () async {
      apple.error = const AppleAuthException(AppleAuthErrorKind.canceled);
      final ok = await container
          .read(signInControllerProvider.notifier)
          .signInWithApple();
      expect(ok, isFalse);
      expect(backend.appleCalls, isEmpty);
      expect(container.read(signInControllerProvider).error, isNull);
      expect(container.read(signInControllerProvider).busy, isNull);
    });

    test('diğer hatalarda Türkçe metin', () async {
      apple.error = const AppleAuthException(AppleAuthErrorKind.unknown);
      await container.read(signInControllerProvider.notifier).signInWithApple();
      expect(container.read(signInControllerProvider).error,
          'Apple ile giriş yapılamadı. Tekrar dene.');
    });
  });

  group('görünürlük', () {
    test('yalnızca iOS (web değil)', () {
      expect(appleSignInSupported(isWeb: false, platform: TargetPlatform.iOS),
          isTrue);
      expect(appleSignInSupported(isWeb: true, platform: TargetPlatform.iOS),
          isFalse);
      expect(
          appleSignInSupported(isWeb: false, platform: TargetPlatform.android),
          isFalse);
    });

    Future<void> pump(WidgetTester tester,
        {required bool apple, required bool google}) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appleLoginAvailableProvider.overrideWithValue(apple),
          googleLoginAvailableProvider.overrideWithValue(google),
          googleIdentityClientProvider
              .overrideWithValue(FakeGoogleIdentityClient()),
          appleIdentityClientProvider.overrideWith((ref) => FakeAppleClient()),
          signInBackendProvider.overrideWithValue(FakeSignInBackend()),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ));
    }

    testWidgets('iOS\'ta Apple düğmesi Google\'ın üstünde', (tester) async {
      await pump(tester, apple: true, google: true);
      final appleBtn = find.byKey(const Key('sign-in-apple'));
      final googleBtn = find.byKey(const Key('sign-in-google'));
      expect(appleBtn, findsOneWidget);
      expect(find.text('Apple ile devam et'), findsOneWidget);
      expect(tester.getTopLeft(appleBtn).dy,
          lessThan(tester.getTopLeft(googleBtn).dy));
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('Apple kapalıysa düğme yok', (tester) async {
      await pump(tester, apple: false, google: true);
      expect(find.byKey(const Key('sign-in-apple')), findsNothing);
      expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    });

    testWidgets('yalnızca Apple varken e-posta ikincil kalır', (tester) async {
      await pump(tester, apple: true, google: false);
      expect(find.byKey(const Key('sign-in-apple')), findsOneWidget);
      expect(find.byKey(const Key('sign-in-email-toggle')), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });
  });

  group('hesap silme (Apple kullanıcısı)', () {
    test('Apple kimliği algılanır', () {
      expect(
          userHasAppleIdentity(appMetadata: {
            'providers': ['email', 'apple'],
          }),
          isTrue);
      expect(userHasAppleIdentity(appMetadata: {'provider': 'apple'}), isTrue);
      expect(userHasAppleIdentity(identityProviders: ['apple']), isTrue);
      expect(
          userHasAppleIdentity(appMetadata: {
            'providers': ['google'],
          }),
          isFalse);
    });

    test('Apple kullanıcısında taze yetki kodu alınır ve gövdeye eklenir',
        () async {
      final apple = FakeAppleClient();
      final code = await appleCodeForDeletion(isAppleUser: true, client: apple);
      expect(code, 'yetki-kodu');
      expect(AccountRepository.deletionBody(appleAuthorizationCode: code), {
        'confirm': 'SİL',
        'apple_authorization_code': 'yetki-kodu',
      });
    });

    test('Apple olmayan kullanıcıda Apple penceresi açılmaz', () async {
      final apple = FakeAppleClient();
      expect(await appleCodeForDeletion(isAppleUser: false, client: apple),
          isNull);
      expect(apple.calls, 0);
      expect(AccountRepository.deletionBody(), {'confirm': 'SİL'});
    });

    test('vazgeçme silmeyi durdurur', () async {
      final apple = FakeAppleClient(
          error: const AppleAuthException(AppleAuthErrorKind.canceled));
      expect(
        appleCodeForDeletion(isAppleUser: true, client: apple),
        throwsA(isA<AppleAuthException>()
            .having((e) => e.kind, 'kind', AppleAuthErrorKind.canceled)),
      );
    });

    test('Apple hatası silmeyi engellemez (kodsuz sürer)', () async {
      final apple = FakeAppleClient(
          error: const AppleAuthException(AppleAuthErrorKind.unknown));
      expect(
          await appleCodeForDeletion(isAppleUser: true, client: apple), isNull);
      final empty = FakeAppleClient(code: '');
      expect(
          await appleCodeForDeletion(isAppleUser: true, client: empty), isNull);
    });
  });
}
