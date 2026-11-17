import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:kisisel_asistan/core/config/env.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/features/auth/data/google_identity_client.dart';
import 'package:kisisel_asistan/features/health/presentation/health_source_providers.dart';

/// `google_sign_in` 7.x platform katmanının sahtesi (iOS yerel çağrıları).
class _Platform extends GoogleSignInPlatform {
  int initCalls = 0;
  String? initClientId;
  String? initServerClientId;

  int lightweightCalls = 0;
  AuthenticationResults? restored = _result();

  AuthenticationResults signedIn = _result();
  Object? authenticateError;
  AuthenticateParameters? authenticateParams;

  FutureOr<ClientAuthorizationTokenData?> Function(
    AuthorizationRequestDetails request,
  ) authorize = (_) => const ClientAuthorizationTokenData(accessToken: 'at-1');
  final List<AuthorizationRequestDetails> requests = [];

  int signOutCalls = 0;
  int disconnectCalls = 0;

  static AuthenticationResults _result({String? idToken = 'id-token-1'}) =>
      AuthenticationResults(
        user: const GoogleSignInUserData(
          email: 'kisi@gmail.com',
          id: 'user-1',
          displayName: 'Kişi',
        ),
        authenticationTokens: AuthenticationTokenData(idToken: idToken),
      );

  @override
  Future<void> init(InitParameters params) async {
    initCalls++;
    initClientId = params.clientId;
    initServerClientId = params.serverClientId;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    lightweightCalls++;
    return restored;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateParams = params;
    if (authenticateError != null) throw authenticateError!;
    return signedIn;
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    return authorize(params.request);
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async => signOutCalls++;

  @override
  Future<void> disconnect(DisconnectParams params) async => disconnectCalls++;
}

/// Kayıtlı Google Health oturumu olmayan kimlik doğrulama istemcisi sahtesi.
class _HealthAuth implements GoogleAuthClient {
  _HealthAuth(this.error);

  final GoogleAuthException error;

  @override
  Future<GoogleToken> silentToken(List<String> scopes) async => throw error;

  @override
  Future<GoogleAccount> connect(List<String> scopes) async => throw error;

  @override
  Future<void> disconnect() async {}
}

const String _iosId = '123456789012-ios0123456789abcdef.apps.googleusercontent.com';
const String _webId = '123456789012-web0123456789abcdef.apps.googleusercontent.com';

void main() {
  late _Platform platform;

  setUp(() {
    platform = _Platform();
    GoogleSignInPlatform.instance = platform;
  });

  Future<GoogleAuthErrorKind> kindOf(Future<Object?> call) async {
    try {
      await call;
    } on GoogleAuthException catch (error) {
      return error.kind;
    }
    fail('GoogleAuthException bekleniyordu');
  }

  group('tek initialize çağrısı (Google ile giriş + Google Health)', () {
    test('giriş önce, Health sonra: eklenti bir kez, iki kimlikle başlar',
        () async {
      final host = GoogleSignInHost(clientId: _iosId, serverClientId: _webId);
      final login = GoogleSignInIdentityClient(host);
      final health = GoogleSignInAuthClient.withHost(host);

      await login.signIn();
      final token = await health.silentToken(googleHealthScopes);

      expect(token.accessToken, 'at-1');
      expect(platform.initCalls, 1);
      expect(platform.initClientId, _iosId);
      expect(platform.initServerClientId, _webId);
    });

    test('Health önce, giriş sonra: yine tek çağrı', () async {
      final host = GoogleSignInHost(clientId: _iosId, serverClientId: _webId);
      final health = GoogleSignInAuthClient.withHost(host);
      final login = GoogleSignInIdentityClient(host);

      await health.silentToken(googleHealthScopes);
      await login.signIn();
      await health.silentToken(googleHealthScopes);

      expect(platform.initCalls, 1);
      expect(platform.initServerClientId, _webId);
    });

    test('Web kimliği yoksa eklentiye serverClientId verilmez', () async {
      final health = GoogleSignInAuthClient(clientId: _iosId);

      await health.silentToken(googleHealthScopes);

      expect(platform.initCalls, 1);
      expect(platform.initClientId, _iosId);
      expect(platform.initServerClientId, isNull);
    });

    test('sağlayıcı iki tüketiciye aynı ev sahibini verir', () {
      final container = ProviderContainer(overrides: [
        googleClientIdProvider.overrideWithValue(_iosId),
        googleServerClientIdProvider.overrideWithValue(_webId),
      ]);
      addTearDown(container.dispose);

      final host = container.read(googleSignInHostProvider);
      final health =
          container.read(googleAuthClientProvider) as GoogleSignInAuthClient;

      expect(identical(health.host, host), isTrue);
      expect(host.clientId, _iosId);
      expect(host.serverClientId, _webId);
    });

    test('iOS kimliği yoksa yapılandırma hatası, eklentiye gidilmez', () async {
      final login = GoogleSignInIdentityClient(
        GoogleSignInHost(clientId: '', serverClientId: _webId),
      );

      expect(await kindOf(login.signIn()), GoogleAuthErrorKind.configuration);
      expect(platform.initCalls, 0);
    });
  });

  group('GoogleSignInIdentityClient', () {
    late GoogleSignInIdentityClient login;

    setUp(() {
      login = GoogleSignInIdentityClient(
        GoogleSignInHost(clientId: _iosId, serverClientId: _webId),
      );
    });

    test('yalnızca e-posta ve profil kapsamı istenir; belirteçler döner',
        () async {
      final identity = await login.signIn();

      expect(googleSignInScopes, ['email', 'profile']);
      expect(platform.authenticateParams!.scopeHint, googleSignInScopes);
      expect(platform.requests.single.scopes, googleSignInScopes);
      expect(platform.requests.single.promptIfUnauthorized, isFalse,
          reason: 'ek izin penceresi açılmaz');
      expect(identity.idToken, 'id-token-1');
      expect(identity.accessToken, 'at-1');
      expect(identity.email, 'kisi@gmail.com');
      expect(identity.displayName, 'Kişi');
      expect(
        googleSignInScopes.any(googleHealthScopes.contains),
        isFalse,
        reason: 'giriş sağlık kapsamı istemez',
      );
    });

    test('erişim anahtarı alınamazsa kimlik belirteci yine döner', () async {
      platform.authorize = (_) => throw StateError('yetkilendirme yok');

      final identity = await login.signIn();

      expect(identity.idToken, 'id-token-1');
      expect(identity.accessToken, isNull);
    });

    test('kimlik belirteci gelmezse yapılandırma hatası (Web kimliği)',
        () async {
      platform.signedIn = _Platform._result(idToken: null);

      final error = await login.signIn().then<Object?>((_) => null,
          onError: (Object e) => e);

      expect(error, isA<GoogleAuthException>());
      expect((error as GoogleAuthException).kind,
          GoogleAuthErrorKind.configuration);
      expect(error.message, contains('GOOGLE_WEB_CLIENT_ID'));
    });

    test('pencere kapatılırsa canceled', () async {
      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );

      expect(await kindOf(login.signIn()), GoogleAuthErrorKind.canceled);
    });

    test('bilinmeyen hata unknown, yapılandırma hatası configuration',
        () async {
      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
      );
      expect(await kindOf(login.signIn()), GoogleAuthErrorKind.unknown);

      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );
      expect(await kindOf(login.signIn()), GoogleAuthErrorKind.configuration);
    });

    test('başarıda ve hatada Google oturumu kapatılmaz (Health yuvası)',
        () async {
      await login.signIn();
      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      await kindOf(login.signIn());

      expect(platform.signOutCalls, 0);
      expect(platform.disconnectCalls, 0);
    });
  });

  group('Google Health yalnızca bağlanınca bağlı sayılır', () {
    Future<GoogleHealthErrorKind> kindFor(GoogleLinkPrefs prefs) async {
      final container = ProviderContainer(overrides: [
        googleClientIdProvider.overrideWithValue(_iosId),
        googleAuthClientProvider.overrideWithValue(
          _HealthAuth(const GoogleAuthException(GoogleAuthErrorKind.scopesMissing)),
        ),
        initialGoogleLinkProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);
      try {
        await container.read(googleConnectionProvider.notifier).accessToken();
      } on GoogleHealthException catch (error) {
        return error.kind;
      }
      fail('GoogleHealthException bekleniyordu');
    }

    test(
        'girişte bulunan Google hesabında Health izni yoksa ama Health hiç '
        'bağlanmadıysa "bağlı değil" (izin eksik denmez)', () async {
      expect(
        await kindFor(const GoogleLinkPrefs()),
        GoogleHealthErrorKind.notConnected,
      );
    });

    test('Health bağlanmış hesapta izin eksikse "izin eksik" kalır', () async {
      expect(
        await kindFor(const GoogleLinkPrefs(email: 'kisi@gmail.com')),
        GoogleHealthErrorKind.missingScope,
      );
    });
  });

  group('GOOGLE_WEB_CLIENT_ID yapılandırması', () {
    test('Web istemci kimliği aynı biçimle doğrulanır', () {
      expect(normalizeGoogleClientId('  $_webId  '), _webId);
      expect(normalizeGoogleClientId('web-client'), '');
      expect(normalizeGoogleClientId(''), '');
    });

    test('derlemede verilmediğinde Google girişi için Web kimliği boştur', () {
      expect(Env.googleWebClientId, '');
      expect(Env.missingKeys, isNot(contains('GOOGLE_WEB_CLIENT_ID')));
    });
  });
}
