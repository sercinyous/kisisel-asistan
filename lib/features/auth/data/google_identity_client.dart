import '../../../core/services/google_auth.dart';

/// Giriş için istenen temel kapsamlar: yalnızca e-posta ve profil. Sağlık
/// kapsamları ayrıdır ve Google Health bağlanırken istenir.
const List<String> googleSignInScopes = ['email', 'profile'];

/// Google'ın verdiği kimlik: Supabase'e verilen belirteçler ve hesap.
class GoogleIdentity {
  const GoogleIdentity({
    required this.idToken,
    required this.email,
    this.accessToken,
    this.displayName,
  });

  /// Hedef kitlesi Web istemci kimliği olan OpenID kimlik belirteci.
  final String idToken;

  /// İsteğe bağlı; Supabase kimlik belirtecini tek başına da doğrular.
  final String? accessToken;

  final String email;
  final String? displayName;
}

/// Google ile giriş penceresini açar. Uygulama yalnızca bu arayüzü kullanır;
/// testler sahtesini verir.
abstract interface class GoogleIdentityClient {
  /// Başarısızlıkta (vazgeçme dahil) [GoogleAuthException] fırlatır.
  Future<GoogleIdentity> signIn();
}

/// `google_sign_in` 7.x ile gerçek istemci. Eklentiyi kendisi başlatmaz;
/// Google Health ile paylaşılan [GoogleSignInHost] başlatır (tek `initialize`
/// çağrısı, `clientId` + `serverClientId`). Çıkışta eklentiye dokunulmaz: Google
/// Health bağlantısı uygulamadan çıkışla kopmaz.
class GoogleSignInIdentityClient implements GoogleIdentityClient {
  GoogleSignInIdentityClient(this._host);

  final GoogleSignInHost _host;

  @override
  Future<GoogleIdentity> signIn() async {
    await _host.ensureInitialized();
    try {
      final account =
          await _host.signIn.authenticate(scopeHint: googleSignInScopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException(
          GoogleAuthErrorKind.configuration,
          'Google kimlik belirteci alınamadı. Web istemci kimliğini '
          '(GOOGLE_WEB_CLIENT_ID) kontrol et.',
        );
      }
      String? accessToken;
      try {
        final authorization = await account.authorizationClient
            .authorizationForScopes(googleSignInScopes);
        accessToken = authorization?.accessToken;
      } catch (_) {
        // Erişim anahtarı isteğe bağlıdır; kimlik belirteci tek başına yeter.
      }
      return GoogleIdentity(
        idToken: idToken,
        accessToken: accessToken,
        email: account.email,
        displayName: account.displayName,
      );
    } on GoogleAuthException {
      rethrow;
    } catch (error) {
      throw translateGoogleSignInError(error, interactive: true);
    }
  }
}
