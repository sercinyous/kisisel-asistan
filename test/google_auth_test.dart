import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/features/health/data/google_health_source.dart';
import 'package:kisisel_asistan/features/health/presentation/health_source_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `google_sign_in` 7.x'in platform katmanının sahtesi: gerçek
/// [GoogleSignInAuthClient] ve eklentinin Dart katmanı olduğu gibi çalışır,
/// yalnızca iOS yerel çağrıları taklit edilir.
class _FakePlatform extends GoogleSignInPlatform {
  int initCalls = 0;
  String? initClientId;
  Object? initError;

  int lightweightCalls = 0;
  Object? lightweightError;

  /// Doluysa sessiz geri yükleme GIDSignIn'in tek `_currentOptions` yuvasını
  /// taklit eder: her çağrı yuvayı ezer, akış bu süre sonra biter ve yalnızca
  /// yuvadaki (son) çağrının geri çağrısını çalıştırıp yuvayı boşaltır;
  /// öncekilerin geri çağrısı hiç çalışmaz (iOS'ta Pigeon vadesi hiç dönmez).
  Duration? restoreSlotDelay;
  Completer<AuthenticationResults?>? _slot;

  /// Doluysa [restoredUser] yerine sessiz geri yükleme sonucu bundan gelir
  /// (hiç dönmeyen ya da elle tamamlanan geri yükleme için).
  Future<AuthenticationResults?> Function()? restoreBehavior;

  /// Doluysa [authenticate] bu tamamlanana kadar bekler (açık giriş penceresi).
  Completer<void>? authenticateGate;

  /// Yerel çağrıların sırası: `restore-start`, `restore-end`, `authenticate`.
  final List<String> events = [];

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
    events.add('restore-start');
    final slotDelay = restoreSlotDelay;
    if (slotDelay != null) {
      final completer = Completer<AuthenticationResults?>();
      _slot = completer;
      Future<void>.delayed(slotDelay, () {
        final current = _slot;
        _slot = null;
        current?.complete(restoredUser);
      });
      return completer.future;
    }
    final behavior = restoreBehavior;
    if (behavior != null) {
      final result = await behavior();
      events.add('restore-end');
      return result;
    }
    if (lightweightError != null) throw lightweightError!;
    events.add('restore-end');
    return restoredUser;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateParams = params;
    events.add('authenticate');
    if (authenticateGate != null) await authenticateGate!.future;
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

  group('eşzamanlı sessiz geri yükleme (soğuk açılış, GIDSignIn tek yuva)', () {
    test(
        'üç paralel istek tek yerel geri yükleme yapar ve üçü de anahtar alır',
        () async {
      // Soğuk açılışta adım, kalori ve uyku okumaları aynı anda başlar; hesap
      // henüz belleğe alınmamıştır. Yuva modelinde her ek çağrı öncekini
      // yetim bırakır: dedupe yoksa ikisi hiç dönmez ve okuma 30 sn takılır.
      platform.restoreSlotDelay = const Duration(milliseconds: 30);
      final shared = GoogleSignInAuthClient(
        clientId: _clientId,
        timeout: const Duration(milliseconds: 500),
      );

      final tokens = await Future.wait([
        shared.silentToken(googleHealthScopes),
        shared.silentToken(googleHealthScopes),
        shared.silentToken(googleHealthScopes),
      ]);

      expect(platform.lightweightCalls, 1,
          reason: 'tüm çağrılar tek yerel geri yüklemeyi paylaşır');
      expect(tokens.map((t) => t.accessToken), ['tok-1', 'tok-1', 'tok-1']);
      expect(platform.requests, hasLength(3));

      // Hesap bellekte: sonraki istek yeniden geri yüklemez.
      await shared.silentToken(googleHealthScopes);
      expect(platform.lightweightCalls, 1);
    });

    test(
        'geri yükleme hiç dönmezse tek ağ hatası; katılan çağrı "expired" almaz, '
        'sonraki çağrı yerelde yeniden dener', () async {
      platform.restoreBehavior = () => Completer<AuthenticationResults?>().future;
      final slow = GoogleSignInAuthClient(
        clientId: _clientId,
        timeout: const Duration(milliseconds: 200),
      );

      final first = kindOf(slow.silentToken(googleHealthScopes));
      // İkinci çağrı geri yüklemeye sonradan katılır: kendi üst sürelemesi
      // paylaşılan (daha önce başlamış) süreden geç dolar.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final joined = kindOf(slow.silentToken(googleHealthScopes));

      expect(await first, GoogleAuthErrorKind.network);
      expect(await joined, GoogleAuthErrorKind.network,
          reason: 'paylaşılan zaman aşımı "yeniden bağlan" değil ağ hatasıdır');
      expect(platform.lightweightCalls, 1);

      // Kapı temizlenmiştir: yerel çağrı bu kez yanıt verir.
      platform.restoreBehavior = null;
      final token = await slow.silentToken(googleHealthScopes);
      expect(token.accessToken, 'tok-1');
      expect(platform.lightweightCalls, 2,
          reason: 'kayıp tamamlanma sonraki çağrıyı kilitlememeli');
    });

    test('geri yükleme hatası tüm katılanlara iletilir, kapı temizlenir',
        () async {
      platform.lightweightError = PlatformException(
        code: 'org.openid.appauth.oauth_token: -10',
      );

      final kinds = await Future.wait([
        kindOf(client.silentToken(googleHealthScopes)),
        kindOf(client.silentToken(googleHealthScopes)),
      ]);

      expect(kinds, [GoogleAuthErrorKind.expired, GoogleAuthErrorKind.expired]);
      expect(platform.lightweightCalls, 1);

      platform.lightweightError = null;
      expect(
          (await client.silentToken(googleHealthScopes)).accessToken, 'tok-1');
      expect(platform.lightweightCalls, 2);
    });

    test('connect, süren sessiz geri yüklemenin bitmesini bekler', () async {
      final restore = Completer<AuthenticationResults?>();
      platform.restoreBehavior = () => restore.future;

      final silent = client.silentToken(googleHealthScopes);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final connecting = client.connect(googleHealthScopes);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(platform.events, ['restore-start'],
          reason: 'etkileşimli giriş, geri yükleme dönmeden başlamaz');

      restore.complete(platform.restoredUser);
      await silent;
      await connecting;

      expect(platform.events, ['restore-start', 'restore-end', 'authenticate']);
    });

    test('giriş penceresi açıkken başlayan geri yükleme yuvayı ezmez',
        () async {
      final gate = Completer<void>();
      platform.authenticateGate = gate;

      final connecting = client.connect(googleHealthScopes);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final silent = client.silentToken(googleHealthScopes);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(platform.lightweightCalls, 0,
          reason: 'giriş sürerken yerel geri yükleme başlamaz');

      gate.complete();
      await connecting;
      final token = await silent;

      expect(token.account.email, 'kisi@gmail.com');
      expect(platform.lightweightCalls, 0,
          reason: 'bağlanan hesap bellekte; yeniden geri yükleme gerekmez');
    });

    test('disconnect, süren geri yüklemeden sonra hesabı unutur', () async {
      final restore = Completer<AuthenticationResults?>();
      platform.restoreBehavior = () => restore.future;

      final silent = client.silentToken(googleHealthScopes);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final disconnecting = client.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(platform.disconnectCalls, 0,
          reason: 'geri yükleme dönmeden bağlantı kesilmez');

      restore.complete(platform.restoredUser);
      await silent;
      await disconnecting;
      expect(platform.disconnectCalls, 1);

      // Geri yüklenen hesap kesilen bağlantıdan sonra geri gelmemeli.
      platform.restoreBehavior = null;
      await client.silentToken(googleHealthScopes);
      expect(platform.lightweightCalls, 2);
    });
  });

  group('hata sınıflandırması (iOS PlatformException kodları)', () {
    // iOS eklentisi GIDSignIn dışındaki NSError'ları "<alan>: <kod>" koduyla
    // verir; AppAuth bağlantı hatalarını NSURLError'a değil kendi genel
    // alanına sarar.
    const transient = [
      'org.openid.appauth.general: -5', // ağ yok / bağlantı hatası
      'org.openid.appauth.general: -6', // Google 5xx (sunucu hatası)
      'org.openid.appauth.general: -7', // JSON değil (ör. oturum açma sayfası)
      'NSURLErrorDomain: -1009',
    ];

    for (final code in transient) {
      test('geri yükleme yolunda $code → network (oturum geçerli)', () async {
        platform.lightweightError = PlatformException(code: code);

        expect(await kindOf(client.silentToken(googleHealthScopes)),
            GoogleAuthErrorKind.network);
      });

      test('yenileme yolunda $code → network, bellekteki hesap korunur',
          () async {
        platform.authorize = (_) => throw PlatformException(code: code);

        expect(await kindOf(client.silentToken(googleHealthScopes)),
            GoogleAuthErrorKind.network);

        platform.authorize =
            (_) => const ClientAuthorizationTokenData(accessToken: 'tok-4');
        expect((await client.silentToken(googleHealthScopes)).accessToken,
            'tok-4');
        expect(platform.lightweightCalls, 1,
            reason: 'ağ hatası oturumu düşürmez');
      });
    }

    test('geri yükleme yolunda oauth_token (invalid_grant) → expired',
        () async {
      platform.lightweightError =
          PlatformException(code: 'org.openid.appauth.oauth_token: -10');

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.expired);
    });

    test('yenileme yolunda oauth_token → expired, hesap baştan aranır',
        () async {
      platform.authorize = (_) =>
          throw PlatformException(code: 'org.openid.appauth.oauth_token: -10');

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.expired);

      platform.authorize =
          (_) => const ClientAuthorizationTokenData(accessToken: 'tok-5');
      await client.silentToken(googleHealthScopes);
      expect(platform.lightweightCalls, 2);
    });

    test('tanınmayan PlatformException sessiz yolda network, girişte unknown',
        () async {
      platform.lightweightError = PlatformException(code: 'channel-error');
      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.network);

      platform.authenticateError =
          PlatformException(code: 'org.openid.appauth.general: -5');
      expect(await kindOf(client.connect(googleHealthScopes)),
          GoogleAuthErrorKind.unknown);
    });

    test('GoogleSignInException(unknownError) sessiz yolda expired kalır',
        () async {
      platform.authorize = (_) => throw const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          );

      expect(await kindOf(client.silentToken(googleHealthScopes)),
          GoogleAuthErrorKind.expired);
    });
  });

  group('çevrimdışı açılış Google bağlantı durumunu bozmaz', () {
    late ProviderContainer container;
    late GoogleHealthSource source;
    late List<http.Request> sent;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sent = [];
      container = ProviderContainer(
        overrides: [
          googleClientIdProvider.overrideWithValue(_clientId),
          googleAuthClientProvider.overrideWithValue(client),
          initialGoogleLinkProvider
              .overrideWithValue(const GoogleLinkPrefs(email: 'kisi@gmail.com')),
        ],
      );
      addTearDown(container.dispose);
      final link = container.read(googleConnectionProvider.notifier);
      source = GoogleHealthSource(
        link: link,
        api: GoogleHealthApi(
          accessToken: link.accessToken,
          client: MockClient((request) async {
            sent.add(request);
            return http.Response('', 500);
          }),
        ),
      );
    });

    final now = DateTime(2026, 11, 17, 8, 30);

    test('AppAuth ağ hatası (-5): kart hata gösterir, "yeniden bağlan" yok',
        () async {
      platform.lightweightError =
          PlatformException(code: 'org.openid.appauth.general: -5');

      final snapshot = await source.readToday(now: now);

      expect(snapshot.status, HealthStatus.failed);
      expect(snapshot.message, contains('İnternet bağlantını kontrol et'));
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.connected);
      expect(sent, isEmpty);
      // Çevrimdışı iken eşitleme çağrıları da durumu bozmaz.
      expect(await source.readPastDays(now: now), isEmpty);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.connected);
    });

    test('Google 5xx (-6) aynı şekilde geçici hata sayılır', () async {
      platform.authorize =
          (_) => throw PlatformException(code: 'org.openid.appauth.general: -6');

      final snapshot = await source.readToday(now: now);

      expect(snapshot.status, HealthStatus.failed);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.connected);
    });

    test('yenileme anahtarı reddi (oauth_token) "yeniden bağlan" durumuna götürür',
        () async {
      platform.authorize = (_) =>
          throw PlatformException(code: 'org.openid.appauth.oauth_token: -10');

      final snapshot = await source.readToday(now: now);

      expect(snapshot.status, HealthStatus.reconnect);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.reconnect);
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
