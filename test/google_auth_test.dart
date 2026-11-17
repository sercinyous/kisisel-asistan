import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';

/// `google_sign_in` 7.x'in platform katmanının sahtesi: gerçek
/// [GoogleSignInAuthClient] ve eklentinin Dart katmanı olduğu gibi çalışır,
/// yalnızca iOS yerel çağrıları taklit edilir.
class _FakePlatform extends GoogleSignInPlatform {
  int initCalls = 0;
  String? initClientId;
  Object? initError;

  int lightweightCalls = 0;
  Object? lightweightError;

  /// `null`: kayıtlı oturum yok (iOS'ta "noAuthInKeychain").
  AuthenticationResults? restoredUser = _result;

  /// [authenticate] sonucu.
  AuthenticationResults signedInUser = _result;
  Object? authenticateError;
  AuthenticateParameters? authenticateParams;

  /// Verilen yetkilendirme isteğine karşılık gelen anahtar; `null` dönerse
  /// kapsamlar onaylanmamış demektir. Fırlatılabilir.
  FutureOr<ClientAuthorizationTokenData?> Function(
    AuthorizationRequestDetails request,
  ) authorize = (_) => const ClientAuthorizationTokenData(accessToken: 'tok-1');
  final List<AuthorizationRequestDetails> requests = [];

  int disconnectCalls = 0;
  Object? disconnectError;
  int signOutCalls = 0;

  static const AuthenticationResults _result = AuthenticationResults(
    user: GoogleSignInUserData(
      email: 'kisi@gmail.com',
      id: 'user-1',
      displayName: 'Kişi',
    ),
    authenticationTokens: AuthenticationTokenData(idToken: null),
  );

  @override
  Future<void> init(InitParameters params) async {
    initCalls++;
    initClientId = params.clientId;
    if (initError != null) throw initError!;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    lightweightCalls++;
    if (lightweightError != null) throw lightweightError!;
    return restoredUser;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateParams = params;
    if (authenticateError != null) throw authenticateError!;
    return signedInUser;
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
  Future<void> signOut(SignOutParams params) async {
    signOutCalls++;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {
    disconnectCalls++;
    if (disconnectError != null) throw disconnectError!;
  }
}

const String _clientId = '123456789012-abcdef.apps.googleusercontent.com';

void main() {
  late _FakePlatform platform;
  late GoogleSignInAuthClient client;

  setUp(() {
    platform = _FakePlatform();
    GoogleSignInPlatform.instance = platform;
    client = GoogleSignInAuthClient(clientId: _clientId);
  });

  Future<GoogleAuthErrorKind> kindOf(Future<Object?> call) async {
    try {
      await call;
    } on GoogleAuthException catch (error) {
      return error.kind;
    }
    fail('GoogleAuthException bekleniyordu');
  }

  test('yalnızca salt okuma Google Health kapsamları istenir', () {
    expect(googleHealthScopes, [
      'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
      'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
    ]);
    expect(googleHealthScopes.any((s) => s.contains('writeonly')), isFalse);
  });

  group('silentToken (açılış ve öne gelişte sessiz yeniden yetkilendirme)', () {
    test('kayıtlı oturum geri yüklenir, kapsamlarla anahtar döner', () async {
      final token = await client.silentToken(googleHealthScopes);

      expect(token.accessToken, 'tok-1');
      expect(token.account.email, 'kisi@gmail.com');
      expect(platform.initCalls, 1);
      expect(platform.initClientId, _clientId);
      final request = platform.requests.single;
      expect(request.scopes, googleHealthScopes);
      expect(request.userId, 'user-1');
      expect(request.promptIfUnauthorized, isFalse,
          reason: 'sessiz istek hiçbir pencere açmamalı');
    });

    test('ikinci istek oturumu yeniden kurmaz, eklenti bir kez başlar',
        () async {
      await client.silentToken(googleHealthScopes);
      await client.silentToken(googleHealthScopes);

      expect(platform.initCalls, 1);
      expect(platform.lightweightCalls, 1);
      expect(platform.requests, hasLength(2));
    });

    test('istemci kimliği yoksa yapılandırma hatası, eklentiye gidilmez',
        () async {
      final empty = GoogleSignInAuthClient(clientId: '');

      expect(await kindOf(empty.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.configuration);
      expect(platform.initCalls, 0);
    });

    test('kayıtlı oturum yoksa noSession', () async {
      platform.restoredUser = null;

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.noSession);
      expect(platform.requests, isEmpty);
    });

    test(
        'yenileme anahtarı reddedilirse expired; sonraki istek oturumu baştan arar',
        () async {
      platform.authorize = (_) => throw const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'invalid_grant',
          );

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.expired);
      expect(platform.lightweightCalls, 1);

      // Kullanıcı yeniden bağlanmış gibi: anahtar yine verilir.
      platform.authorize =
          (_) => const ClientAuthorizationTokenData(accessToken: 'tok-2');
      final token = await client.silentToken(googleHealthScopes);
      expect(token.accessToken, 'tok-2');
      expect(platform.lightweightCalls, 2,
          reason: 'hata sonrası bellekteki hesap atılır');
    });

    test('oturumu geri yüklerken hata → expired', () async {
      platform.lightweightError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
      );

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.expired);
    });

    test('kapsamlar onaylanmamışsa scopesMissing', () async {
      platform.authorize = (_) => null;

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.scopesMissing);
    });

    test('ağ hatası oturumu düşürmez (expired sayılmaz)', () async {
      platform.authorize =
          (_) => throw PlatformException(code: 'NSURLErrorDomain: -1009');

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.network);

      platform.authorize =
          (_) => const ClientAuthorizationTokenData(accessToken: 'tok-3');
      expect(
          (await client.silentToken(googleHealthScopes)).accessToken, 'tok-3');
      expect(platform.lightweightCalls, 1);
    });

    test('yanıt vermeyen eklenti zaman aşımıyla ağ hatasına döner', () async {
      final slow = GoogleSignInAuthClient(
        clientId: _clientId,
        timeout: const Duration(milliseconds: 40),
      );
      platform.authorize =
          (_) => Completer<ClientAuthorizationTokenData?>().future;

      expect(await kindOf(slow.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.network);
    });

    test('başlatma hatası bir sonraki denemede yeniden denenir', () async {
      platform.initError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.configuration);

      platform.initError = null;
      expect(
          (await client.silentToken(googleHealthScopes)).accessToken, 'tok-1');
      expect(platform.initCalls, 2);
    });
  });

  group('connect (yalnızca kullanıcı dokunuşuyla)', () {
    test('giriş + kapsam izni, ardından sessiz doğrulama', () async {
      final account = await client.connect(googleHealthScopes);

      expect(account.email, 'kisi@gmail.com');
      expect(platform.authenticateParams!.scopeHint, googleHealthScopes);
      expect(platform.requests.map((r) => r.promptIfUnauthorized),
          [isTrue, isFalse]);
      expect(platform.requests.every((r) => r.scopes == googleHealthScopes),
          isTrue);

      // Bağlandıktan sonra sessiz istek oturumu yeniden aramaz.
      await client.silentToken(googleHealthScopes);
      expect(platform.lightweightCalls, 0);
    });

    test('kullanıcı pencereyi kapatırsa canceled', () async {
      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );

      expect(await kindOf(client.connect(googleHealthScopes)),
          GoogleAuthErrorKind.canceled);
    });

    test('izin ekranında kutu kaldırılırsa scopesMissing', () async {
      platform.authorize = (request) => request.promptIfUnauthorized
          ? const ClientAuthorizationTokenData(accessToken: 'tok-1')
          : null;

      expect(await kindOf(client.connect(googleHealthScopes)),
          GoogleAuthErrorKind.scopesMissing);
    });

    test('bilinmeyen hata unknown; yapılandırma hatası configuration',
        () async {
      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
      );
      expect(await kindOf(client.connect(googleHealthScopes)),
          GoogleAuthErrorKind.unknown);

      platform.authenticateError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );
      expect(await kindOf(client.connect(googleHealthScopes)),
          GoogleAuthErrorKind.configuration);
    });
  });

  group('disconnect', () {
    test('izni geri alır ve bellekteki hesabı unutur', () async {
      await client.silentToken(googleHealthScopes);
      await client.disconnect();

      expect(platform.disconnectCalls, 1);
      await client.silentToken(googleHealthScopes);
      expect(platform.lightweightCalls, 2);
    });

    test('izin geri alınamazsa (ağ yok) yine de oturumu kapatır', () async {
      platform.disconnectError =
          PlatformException(code: 'NSURLErrorDomain: -1009');

      await client.disconnect();

      expect(platform.disconnectCalls, 1);
      expect(platform.signOutCalls, 1);
    });
  });
}
