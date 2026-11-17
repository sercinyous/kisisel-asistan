import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/features/auth/data/google_identity_client.dart';
import 'package:kisisel_asistan/features/auth/data/sign_in_backend.dart';
import 'package:kisisel_asistan/features/auth/domain/sign_in_messages.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeGoogleIdentityClient implements GoogleIdentityClient {
  Object? error;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<GoogleIdentity> signIn() async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return const GoogleIdentity(
      idToken: 'id-token',
      accessToken: 'access-token',
      email: 'kisi@gmail.com',
      displayName: 'Kişi',
    );
  }
}

class FakeSignInBackend implements SignInBackend {
  Object? error;
  final List<({String idToken, String? accessToken})> googleCalls = [];
  final List<({String email, String password})> passwordCalls = [];

  @override
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    googleCalls.add((idToken: idToken, accessToken: accessToken));
    if (error != null) throw error!;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    passwordCalls.add((email: email, password: password));
    if (error != null) throw error!;
  }
}

const String _iosId = '123456789012-ios0123456789abcdef.apps.googleusercontent.com';
const String _webId = '123456789012-web0123456789abcdef.apps.googleusercontent.com';

void main() {
  late FakeGoogleIdentityClient google;
  late FakeSignInBackend backend;
  late ProviderContainer container;

  setUp(() {
    google = FakeGoogleIdentityClient();
    backend = FakeSignInBackend();
    container = ProviderContainer(overrides: [
      googleIdentityClientProvider.overrideWithValue(google),
      signInBackendProvider.overrideWithValue(backend),
    ]);
    addTearDown(container.dispose);
  });

  SignInController controller() =>
      container.read(signInControllerProvider.notifier);
  SignInState state() => container.read(signInControllerProvider);

  group('Google ile giriş', () {
    test('kimlik ve erişim belirteci Supabase girişine verilir', () async {
      final ok = await controller().signInWithGoogle();

      expect(ok, isTrue);
      expect(backend.googleCalls.single,
          (idToken: 'id-token', accessToken: 'access-token'));
      expect(state().busy, isNull);
      expect(state().error, isNull);
    });

    test('kullanıcı pencereyi kapatırsa hata gösterilmez, sunucuya gidilmez',
        () async {
      google.error = const GoogleAuthException(GoogleAuthErrorKind.canceled);

      final ok = await controller().signInWithGoogle();

      expect(ok, isFalse);
      expect(state().error, isNull);
      expect(state().isBusy, isFalse);
      expect(backend.googleCalls, isEmpty);
    });

    test('Google hatası Türkçe metin olarak gösterilir', () async {
      google.error = const GoogleAuthException(GoogleAuthErrorKind.network);

      expect(await controller().signInWithGoogle(), isFalse);
      expect(state().error, contains('İnternet bağlantını kontrol et'));
      expect(backend.googleCalls, isEmpty);
    });

    test('kayıt kapısı: davetsiz e-posta anlaşılır mesaj alır (kanca metni)',
        () async {
      backend.error = const AuthApiException(
        'Bu e-posta için davet yok',
        statusCode: '403',
      );

      expect(await controller().signInWithGoogle(), isFalse);
      expect(state().error, noInviteMessage);
      expect(state().error, contains('arkadaş'));
    });

    test(
        'kayıt kapısı: tetikleyici reddi GoTrue\'da genel "Database error '
        'saving new user" gelir, yine davet mesajı', () async {
      backend.error = const AuthApiException(
        'Database error saving new user',
        statusCode: '500',
        code: 'unexpected_failure',
      );

      expect(await controller().signInWithGoogle(), isFalse);
      expect(state().error, noInviteMessage);
    });

    test('sunucuda Google sağlayıcısı yapılandırılmamışsa açıklama verir',
        () async {
      backend.error = const AuthApiException(
        'Unacceptable audience in id_token: [123-web.apps.googleusercontent.com]',
        statusCode: '400',
      );

      expect(await controller().signInWithGoogle(), isFalse);
      expect(state().error, contains('yapılandırılmamış'));
    });

    test('ağ hatası bağlantı mesajına çevrilir', () async {
      backend.error = AuthRetryableFetchException(message: 'offline');

      expect(await controller().signInWithGoogle(), isFalse);
      expect(state().error, connectionFailedMessage);
    });

    test('başarılı denemeden sonra eski hata temizlenir', () async {
      backend.error = const AuthApiException('Bu e-posta için davet yok');
      await controller().signInWithGoogle();
      expect(state().error, isNotNull);

      backend.error = null;
      expect(await controller().signInWithGoogle(), isTrue);
      expect(state().error, isNull);
    });
  });

  group('e-posta ve şifre ile giriş', () {
    test('e-posta kırpılır, şifre olduğu gibi gider', () async {
      final ok = await controller()
          .signInWithPassword(email: '  ben@gmail.com ', password: ' sifre ');

      expect(ok, isTrue);
      expect(backend.passwordCalls.single,
          (email: 'ben@gmail.com', password: ' sifre '));
      expect(google.calls, 0);
    });

    test('yanlış şifre Türkçe mesaj verir', () async {
      backend.error = const AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );

      expect(
        await controller()
            .signInWithPassword(email: 'ben@gmail.com', password: 'x'),
        isFalse,
      );
      expect(state().error, 'E-posta ya da şifre hatalı.');
    });

    test('beklenmeyen hata bağlantı mesajına düşer', () async {
      backend.error = StateError('beklenmeyen');

      await controller()
          .signInWithPassword(email: 'ben@gmail.com', password: 'x');

      expect(state().error, connectionFailedMessage);
    });
  });

  group('eşzamanlılık', () {
    test('süren giriş varken ikinci deneme başlamaz', () async {
      google.gate = Completer<void>();

      final first = controller().signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(state().busy, SignInMethod.google);

      final second = await controller()
          .signInWithPassword(email: 'ben@gmail.com', password: 'x');
      expect(second, isFalse);
      expect(backend.passwordCalls, isEmpty);
      expect(state().busy, SignInMethod.google);

      google.gate!.complete();
      expect(await first, isTrue);
      expect(state().isBusy, isFalse);
      expect(google.calls, 1);
    });
  });

  group('signInErrorMessage', () {
    test('hız sınırı ve doğrulanmamış e-posta', () {
      expect(
        signInErrorMessage(
          const AuthApiException('x', statusCode: '429', code: 'over_request_rate_limit'),
        ),
        contains('Çok fazla deneme'),
      );
      expect(
        signInErrorMessage(
          const AuthApiException('Email not confirmed', code: 'email_not_confirmed'),
        ),
        contains('doğrulanmamış'),
      );
    });

    test('tanınmayan sunucu hatası özgün metni korur', () {
      expect(
        signInErrorMessage(const AuthApiException('Beklenmeyen', statusCode: '500')),
        'Giriş başarısız: Beklenmeyen',
      );
    });

    test('davet reddi her iki biçimde de tanınır', () {
      expect(isNoInviteRejection(const AuthException('Bu e-posta için davet yok')),
          isTrue);
      expect(isNoInviteRejection(const AuthException('Database error saving new user')),
          isTrue);
      expect(isNoInviteRejection(const AuthException('Invalid login credentials')),
          isFalse);
    });
  });

  group('googleLoginAvailableProvider', () {
    bool available({String ios = _iosId, String web = _webId}) {
      final c = ProviderContainer(overrides: [
        googleClientIdProvider.overrideWithValue(ios),
        googleServerClientIdProvider.overrideWithValue(web),
      ]);
      addTearDown(c.dispose);
      return c.read(googleLoginAvailableProvider);
    }

    test('iki istemci kimliği de varsa açık', () {
      expect(available(), isTrue);
    });

    test('Web kimliği boşsa Google girişi gizlenir', () {
      expect(available(web: ''), isFalse);
    });

    test('iOS kimliği boşsa Google girişi gizlenir', () {
      expect(available(ios: ''), isFalse);
    });

    test('derleme varsayılanında (kimlik verilmemiş) gizlidir', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(googleLoginAvailableProvider), isFalse);
    });
  });
}
