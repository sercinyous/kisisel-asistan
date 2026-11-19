import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/env.dart';

/// Google Health'ten okunan alanların salt okuma kapsamları: adım, aktif
/// kalori ve antrenmanlar "activity and fitness", uyku "sleep" kapsamındadır.
/// Yazma kapsamı istenmez.
const List<String> googleHealthScopes = [
  'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
  'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
];

/// Derlemeye verilen iOS istemci kimliği; boşsa Google seçeneği kapalıdır.
/// Testler ve demo bu sağlayıcıyı ezer.
final googleClientIdProvider = Provider<String>((ref) => Env.googleIosClientId);

/// Derlemeye verilen Web istemci kimliği (`serverClientId`); Supabase ile
/// Google girişi için gerekir, boşsa giriş ekranında Google düğmesi gizlenir.
final googleServerClientIdProvider =
    Provider<String>((ref) => Env.googleWebClientId);

/// Uygulamanın tek `GoogleSignIn.instance.initialize` çağrısının sahibi:
/// Google ile giriş ve Google Health aynı örneği paylaşır.
final googleSignInHostProvider = Provider<GoogleSignInHost>(
  (ref) => GoogleSignInHost(
    clientId: ref.watch(googleClientIdProvider),
    serverClientId: ref.watch(googleServerClientIdProvider),
  ),
);

final googleAuthClientProvider = Provider<GoogleAuthClient>(
  (ref) => GoogleSignInAuthClient.withHost(ref.watch(googleSignInHostProvider)),
);

/// Bağlı Google hesabı.
class GoogleAccount {
  const GoogleAccount({required this.email, this.displayName});

  final String email;
  final String? displayName;
}

/// Google Health isteklerinde kullanılan erişim anahtarı ve sahibi.
class GoogleToken {
  const GoogleToken({required this.accessToken, required this.account});

  final String accessToken;
  final GoogleAccount account;
}

enum GoogleAuthErrorKind {
  /// Kayıtlı Google oturumu yok (hiç bağlanılmamış ya da bağlantı kesilmiş).
  noSession,

  /// Oturum var ama istenen kapsamların bir kısmı onaylanmamış.
  scopesMissing,

  /// Oturum yenilenemedi (ör. "Testing" modunda ~7 günde biten yenileme
  /// anahtarı ya da kullanıcı erişimi Google hesabından kaldırmış).
  expired,

  /// Kullanıcı giriş penceresini kapattı.
  canceled,

  /// İstemci kimliği ya da URL şeması hatalı.
  configuration,

  /// Ağ hatası; oturum geçerli olabilir, sonra tekrar denenir.
  network,

  unknown;

  String get defaultMessage => switch (this) {
        noSession => 'Google hesabı bağlı değil.',
        scopesMissing => 'Google Health izinlerinin bir kısmı verilmedi. '
            'Google\'a yeniden bağlanıp tüm izinleri onayla.',
        expired => 'Google oturumunun süresi doldu. Google\'a yeniden bağlan.',
        canceled => 'Google ile bağlantı iptal edildi.',
        configuration => 'Google ile giriş yapılandırması hatalı '
            '(istemci kimliği ya da URL şeması).',
        network => 'Google\'a ulaşılamadı. İnternet bağlantını kontrol et.',
        unknown => 'Google ile bağlanılamadı. Tekrar dene.',
      };
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.kind, [String? message]) : _message = message;

  final GoogleAuthErrorKind kind;
  final String? _message;

  /// Kullanıcıya gösterilebilir Türkçe açıklama.
  String get message => _message ?? kind.defaultMessage;

  @override
  String toString() => message;
}

/// Google ile giriş ve yetkilendirme. Uygulama yalnızca bu arayüzü kullanır;
/// testler ve tarayıcı demosu sahtesini verir.
abstract interface class GoogleAuthClient {
  /// Kullanıcıya pencere göstermeden önceki oturumu geri yükler ve [scopes]
  /// için geçerli bir erişim anahtarı döndürür (süresi dolmuşsa yenilenir).
  /// Başarısızlıkta [GoogleAuthException] fırlatır.
  Future<GoogleToken> silentToken(List<String> scopes);

  /// Google giriş penceresini açar ve [scopes] iznini ister. Yalnızca
  /// kullanıcı dokunuşuyla çağrılır.
  Future<GoogleAccount> connect(List<String> scopes);

  /// Verilen izni geri alır ve oturumu kapatır.
  Future<void> disconnect();
}

/// `GoogleSignIn.instance.initialize` çağrısını tek seferde yapan ortak ev
/// sahibi. Eklenti ömürde yalnızca bir kez başlatılabilir; Google ile giriş
/// (Supabase) ve Google Health bu nesneyi paylaşır, böylece `clientId` ve
/// `serverClientId` ikisi için aynı çağrıyla verilir.
class GoogleSignInHost {
  GoogleSignInHost({
    required this.clientId,
    this.serverClientId = '',
    GoogleSignIn? signIn,
  }) : _injected = signIn;

  /// iOS OAuth istemci kimliği; boşsa eklenti hiç başlatılmaz.
  final String clientId;

  /// Web OAuth istemci kimliği (kimlik belirtecinin hedef kitlesi); boşsa
  /// verilmez (yalnızca Google Health kullanılan derleme).
  final String serverClientId;

  final GoogleSignIn? _injected;
  Future<void>? _initialization;

  // Tekil örneğe ancak gerektiğinde erişilir (Google seçilmeyen derlemede
  // ve testlerde eklenti hiç başlatılmaz).
  GoogleSignIn get signIn => _injected ?? GoogleSignIn.instance;

  /// Eklentiyi başlatır; sonraki çağrılar aynı sonucu paylaşır. Hata verirse
  /// bir sonraki denemede yeniden çağrılabilsin diye bırakılır.
  Future<void> ensureInitialized() {
    if (clientId.isEmpty) {
      return Future.error(
        const GoogleAuthException(GoogleAuthErrorKind.configuration),
      );
    }
    return _initialization ??= signIn
        .initialize(
      clientId: clientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    )
        .catchError((Object error, StackTrace stack) {
      _initialization = null;
      Error.throwWithStackTrace(
        translateGoogleSignInError(error, interactive: false),
        stack,
      );
    });
  }
}

/// `google_sign_in` 7.x ile çalışan gerçek istemci (iOS).
class GoogleSignInAuthClient implements GoogleAuthClient {
  GoogleSignInAuthClient({
    required String clientId,
    String serverClientId = '',
    GoogleSignIn? signIn,
    Duration timeout = const Duration(seconds: 30),
  }) : this.withHost(
          GoogleSignInHost(
            clientId: clientId,
            serverClientId: serverClientId,
            signIn: signIn,
          ),
          timeout: timeout,
        );

  /// Başlatmayı başka bileşenlerle (Google ile giriş) paylaşan kurucu.
  GoogleSignInAuthClient.withHost(
    this.host, {
    this.timeout = const Duration(seconds: 30),
  });

  final GoogleSignInHost host;

  String get clientId => host.clientId;

  /// Etkileşimsiz isteklerin üst süresi; aşılırsa ağ hatası sayılır ve
  /// uygulama beklemeye devam etmez.
  final Duration timeout;

  GoogleSignInAccount? _account;

  /// Süren sessiz geri yükleme (`restorePreviousSignIn`). iOS'ta GIDSignIn'in
  /// tek bir `_currentOptions` yuvası vardır: üst üste başlatılan her çağrı
  /// öncekinin tamamlanma geri çağrısını ezer ve yalnızca sonuncusu döner;
  /// ötekilerin vadesi hiç sonuçlanmaz. Bu yüzden eşzamanlı tüm istekler
  /// (paralel adım/kalori/uyku okumaları, öne geliş, elle yenileme) tek yerel
  /// çağrıyı paylaşır.
  Future<GoogleSignInAccount?>? _restoring;

  /// Süren etkileşimli işlem (giriş, bağlantıyı kesme). Aynı yuvayı kullanır;
  /// bitene kadar yeni sessiz geri yükleme başlamaz.
  Future<void>? _interactive;

  GoogleSignIn get _signIn => host.signIn;

  Future<void> _ensureInitialized() => host.ensureInitialized();

  @override
  Future<GoogleToken> silentToken(List<String> scopes) async {
    try {
      return await _silentToken(scopes).timeout(timeout);
    } on TimeoutException {
      throw const GoogleAuthException(GoogleAuthErrorKind.network);
    }
  }

  Future<GoogleToken> _silentToken(List<String> scopes) async {
    await _ensureInitialized();
    var account = _account;
    if (account == null) {
      try {
        account = await _restoreAccount();
      } catch (error) {
        throw translateGoogleSignInError(error, interactive: false);
      }
      if (account == null) {
        throw const GoogleAuthException(GoogleAuthErrorKind.noSession);
      }
    }
    final GoogleSignInClientAuthorization? authorization;
    try {
      authorization =
          await account.authorizationClient.authorizationForScopes(scopes);
    } catch (error) {
      final translated = translateGoogleSignInError(error, interactive: false);
      // Ağ hatası dışında oturum bir dahaki sefere baştan geri yüklenir.
      if (translated.kind != GoogleAuthErrorKind.network) _account = null;
      throw translated;
    }
    if (authorization == null) {
      throw const GoogleAuthException(GoogleAuthErrorKind.scopesMissing);
    }
    return GoogleToken(
      accessToken: authorization.accessToken,
      account: _toAccount(account),
    );
  }

  /// Kayıtlı oturumu geri yükler; eşzamanlı çağrılar tek yerel çağrıyı
  /// paylaşır ([_restoring]). Paylaşılan çağrı [timeout] ile sınırlıdır: yerel
  /// tamamlanma hiç gelmezse kapı açılır ve sonraki çağrı yeniden dener.
  /// Zaman aşımı [TimeoutException] olarak iletilir ([translateGoogleSignInError] ağ hatası yapar).
  Future<GoogleSignInAccount?> _restoreAccount() {
    final inFlight = _restoring;
    if (inFlight != null) return inFlight;
    // Etkileşimli bir işlem sürüyorsa yuva onundur: bitmesini bekler.
    final interactive = _interactive;
    final restoring = Future<GoogleSignInAccount?>.sync(() async {
      if (interactive != null) {
        await interactive;
        final known = _account;
        if (known != null) return known;
      }
      final restored = await _signIn.attemptLightweightAuthentication();
      if (restored != null) _account = restored;
      return restored;
    }).timeout(timeout).whenComplete(() => _restoring = null);
    return _restoring = restoring;
  }

  /// Etkileşimli işlemi çalıştırır: o sırada yeni sessiz geri yükleme
  /// başlamaz, daha önce başlamış olan bitmeden de işlem başlamaz (üçü de
  /// GIDSignIn'in aynı yuvasını kullanır; üst üste binerlerse biri düşer).
  Future<T> _runInteractive<T>(Future<T> Function() action) async {
    final pending = _restoring;
    final done = Completer<void>();
    final marker = done.future;
    _interactive = marker;
    try {
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // Sonucu önemsenmez; yalnızca bitmesi beklenir.
        }
      }
      return await action();
    } finally {
      if (identical(_interactive, marker)) _interactive = null;
      done.complete();
    }
  }

  @override
  Future<GoogleAccount> connect(List<String> scopes) =>
      _runInteractive(() => _connect(scopes));

  Future<GoogleAccount> _connect(List<String> scopes) async {
    await _ensureInitialized();
    try {
      final account = await _signIn.authenticate(scopeHint: scopes);
      await account.authorizationClient.authorizeScopes(scopes);
      // İzin ekranında bazı kutular kaldırılmış olabilir: verilen kapsamlar
      // etkileşimsiz istekle doğrulanır.
      final granted =
          await account.authorizationClient.authorizationForScopes(scopes);
      _account = account;
      if (granted == null) {
        throw const GoogleAuthException(GoogleAuthErrorKind.scopesMissing);
      }
      return _toAccount(account);
    } on GoogleAuthException {
      rethrow;
    } catch (error) {
      throw translateGoogleSignInError(error, interactive: true);
    }
  }

  @override
  Future<void> disconnect() => _runInteractive(_disconnect);

  Future<void> _disconnect() async {
    _account = null;
    try {
      await _ensureInitialized();
      await _signIn.disconnect();
    } catch (_) {
      // İzin geri alınamasa da (ağ yok) yerel oturum kapatılır.
      try {
        await _signIn.signOut();
      } catch (_) {
        // Eklenti hiç başlatılamadıysa kapatılacak oturum da yoktur.
      }
    }
  }

  static GoogleAccount _toAccount(GoogleSignInAccount account) =>
      GoogleAccount(email: account.email, displayName: account.displayName);
}

/// Eklenti hatalarını uygulamanın hata türüne çevirir. iOS'ta GIDSignIn
/// dışındaki hatalar `PlatformException` olarak, kodu "alan: numara"
/// biçiminde gelir (örn. `org.openid.appauth.general: -5`).
///
/// Sessiz yolda (yeniden yetkilendirme) yalnızca yenileme anahtarının
/// kesin reddi oturumu öldürür: AppAuth `org.openid.appauth.oauth_token`
/// alanı (invalid_grant gibi 4xx JSON hataları). Bağlantı hatası (`general:
/// -5`), Google 5xx (`-6`), JSON olmayan yanıt (`-7`, ör. oturum açma
/// sayfası) ve tanınmayan her `PlatformException` geçicidir: [network]
/// döner, bağlı oturum "yeniden bağlan" durumuna düşmez.
GoogleAuthException translateGoogleSignInError(
  Object error, {
  required bool interactive,
}) {
  if (error is GoogleAuthException) return error;
  // Paylaşılan geri yükleme ya da üst süre aşıldı.
  if (error is TimeoutException) {
    return const GoogleAuthException(GoogleAuthErrorKind.network);
  }
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled =>
        const GoogleAuthException(GoogleAuthErrorKind.canceled),
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        const GoogleAuthException(GoogleAuthErrorKind.configuration),
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable =>
        const GoogleAuthException(
          GoogleAuthErrorKind.unknown,
          'Google giriş penceresi açılamadı. Tekrar dene.',
        ),
      _ => GoogleAuthException(
          interactive
              ? GoogleAuthErrorKind.unknown
              : GoogleAuthErrorKind.expired,
        ),
    };
  }
  if (error is PlatformException) {
    final code = error.code;
    if (code.startsWith('NSURLErrorDomain')) {
      return const GoogleAuthException(GoogleAuthErrorKind.network);
    }
    if (interactive) {
      return const GoogleAuthException(GoogleAuthErrorKind.unknown);
    }
    if (code.startsWith('org.openid.appauth.oauth_token')) {
      return const GoogleAuthException(GoogleAuthErrorKind.expired);
    }
    return const GoogleAuthException(GoogleAuthErrorKind.network);
  }
  return GoogleAuthException(
    interactive ? GoogleAuthErrorKind.unknown : GoogleAuthErrorKind.expired,
  );
}
