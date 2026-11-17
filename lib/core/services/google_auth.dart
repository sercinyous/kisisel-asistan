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

final googleAuthClientProvider = Provider<GoogleAuthClient>(
  (ref) => GoogleSignInAuthClient(clientId: ref.watch(googleClientIdProvider)),
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

/// `google_sign_in` 7.x ile çalışan gerçek istemci (iOS).
class GoogleSignInAuthClient implements GoogleAuthClient {
  GoogleSignInAuthClient({
    required this.clientId,
    GoogleSignIn? signIn,
    this.timeout = const Duration(seconds: 30),
  }) : _injected = signIn;

  final String clientId;

  /// Etkileşimsiz isteklerin üst süresi; aşılırsa ağ hatası sayılır ve
  /// uygulama beklemeye devam etmez.
  final Duration timeout;

  final GoogleSignIn? _injected;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  // Tekil örneğe ancak gerektiğinde erişilir (Google seçilmeyen derlemede
  // ve testlerde eklenti hiç başlatılmaz).
  GoogleSignIn get _signIn => _injected ?? GoogleSignIn.instance;

  Future<void> _ensureInitialized() {
    if (clientId.isEmpty) {
      return Future.error(
        const GoogleAuthException(GoogleAuthErrorKind.configuration),
      );
    }
    // `initialize` uygulama ömründe yalnızca bir kez çağrılmalıdır; hata
    // verirse bir sonraki denemede yeniden çağrılabilsin diye bırakılır.
    return _initialization ??= _signIn
        .initialize(clientId: clientId)
        .catchError((Object error, StackTrace stack) {
      _initialization = null;
      Error.throwWithStackTrace(_translate(error, interactive: false), stack);
    });
  }

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
        account = await _signIn.attemptLightweightAuthentication();
      } catch (error) {
        throw _translate(error, interactive: false);
      }
      if (account == null) {
        throw const GoogleAuthException(GoogleAuthErrorKind.noSession);
      }
      _account = account;
    }
    final GoogleSignInClientAuthorization? authorization;
    try {
      authorization =
          await account.authorizationClient.authorizationForScopes(scopes);
    } catch (error) {
      final translated = _translate(error, interactive: false);
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

  @override
  Future<GoogleAccount> connect(List<String> scopes) async {
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
      throw _translate(error, interactive: true);
    }
  }

  @override
  Future<void> disconnect() async {
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

  /// Eklenti hatalarını uygulamanın hata türüne çevirir. iOS'ta GIDSignIn
  /// dışındaki hatalar (ağ, yenileme anahtarı reddi) `PlatformException`
  /// olarak, kodu "alan: numara" biçiminde gelir.
  static GoogleAuthException _translate(
    Object error, {
    required bool interactive,
  }) {
    if (error is GoogleAuthException) return error;
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
    if (error is PlatformException &&
        error.code.startsWith('NSURLErrorDomain')) {
      return const GoogleAuthException(GoogleAuthErrorKind.network);
    }
    return GoogleAuthException(
      interactive ? GoogleAuthErrorKind.unknown : GoogleAuthErrorKind.expired,
    );
  }
}
