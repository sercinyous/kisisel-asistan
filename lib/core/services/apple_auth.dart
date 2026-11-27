import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Ham nonce karakter kümesi (RFC 7636 "unreserved" karakterleri).
const String _nonceCharset =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// Tek kullanımlık ham nonce. Ham değer Supabase'e, SHA-256 özeti Apple'a
/// gider; Supabase kimlik belirtecindeki özetle eşleştirerek tekrar saldırısını
/// engeller.
String generateRawNonce([int length = 32, Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
    length,
    (_) => _nonceCharset[rng.nextInt(_nonceCharset.length)],
  ).join();
}

/// [input] metninin küçük harfli onaltılık SHA-256 özeti.
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// Apple'ın verdiği kimlik.
class AppleCredential {
  const AppleCredential({
    required this.idToken,
    required this.rawNonce,
    this.authorizationCode,
    this.givenName,
    this.familyName,
  });

  /// Apple kimlik belirteci (hedef kitle: paket kimliği).
  final String idToken;

  /// Özeti Apple isteğine konan ham nonce.
  final String rawNonce;

  /// Apple'ın tek kullanımlık yetki kodu (hesap silmede iptal için).
  final String? authorizationCode;

  /// Ad ve soyad yalnızca ilk yetkilendirmede gelir.
  final String? givenName;
  final String? familyName;

  /// Boş olmayan ad parçalarının birleşimi; hiç yoksa `null`.
  String? get fullName {
    final parts = [givenName, familyName]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }
}

enum AppleAuthErrorKind {
  canceled,
  unavailable,
  unknown;

  String get defaultMessage => switch (this) {
        canceled => 'Apple ile giriş iptal edildi.',
        unavailable => 'Apple ile giriş bu cihazda kullanılamıyor.',
        unknown => 'Apple ile giriş yapılamadı. Tekrar dene.',
      };
}

class AppleAuthException implements Exception {
  const AppleAuthException(this.kind, [String? message]) : _message = message;

  final AppleAuthErrorKind kind;
  final String? _message;

  String get message => _message ?? kind.defaultMessage;

  @override
  String toString() => message;
}

/// Eklenti hatalarını uygulamanın hata türüne çevirir.
AppleAuthException translateAppleSignInError(Object error) {
  if (error is AppleAuthException) return error;
  if (error is SignInWithAppleAuthorizationException) {
    return switch (error.code) {
      AuthorizationErrorCode.canceled =>
        const AppleAuthException(AppleAuthErrorKind.canceled),
      _ => const AppleAuthException(AppleAuthErrorKind.unknown),
    };
  }
  if (error is SignInWithAppleNotSupportedException) {
    return const AppleAuthException(AppleAuthErrorKind.unavailable);
  }
  return const AppleAuthException(AppleAuthErrorKind.unknown);
}

/// Apple ile giriş penceresini açar. Uygulama yalnızca bu arayüzü kullanır;
/// testler sahtesini verir.
abstract interface class AppleIdentityClient {
  /// Başarısızlıkta (vazgeçme dahil) [AppleAuthException] fırlatır.
  Future<AppleCredential> signIn();
}

/// Yerel iOS akışı (`sign_in_with_apple`).
class SignInWithAppleIdentityClient implements AppleIdentityClient {
  SignInWithAppleIdentityClient({String Function()? nonce})
      : _nonce = nonce ?? generateRawNonce;

  final String Function() _nonce;

  @override
  Future<AppleCredential> signIn() async {
    final rawNonce = _nonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256Hex(rawNonce),
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AppleAuthException(
          AppleAuthErrorKind.unknown,
          'Apple kimlik belirteci alınamadı. Tekrar dene.',
        );
      }
      return AppleCredential(
        idToken: idToken,
        rawNonce: rawNonce,
        authorizationCode: credential.authorizationCode,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } catch (error) {
      throw translateAppleSignInError(error);
    }
  }
}

final appleIdentityClientProvider = Provider<AppleIdentityClient>(
  (ref) => SignInWithAppleIdentityClient(),
);

/// Apple ile giriş yalnızca iOS'ta sunulur (tarayıcı demosunda gizli).
bool appleSignInSupported(
        {required bool isWeb, required TargetPlatform platform}) =>
    !isWeb && platform == TargetPlatform.iOS;

final appleLoginAvailableProvider = Provider<bool>(
  (ref) => appleSignInSupported(isWeb: kIsWeb, platform: defaultTargetPlatform),
);

/// Oturumdaki kullanıcının Apple kimliği var mı (`app_metadata.providers` ya da
/// `identities`)?
bool userHasAppleIdentity({
  Map<String, dynamic>? appMetadata,
  Iterable<String> identityProviders = const [],
}) {
  final providers = appMetadata?['providers'];
  if (providers is List && providers.contains('apple')) return true;
  if (appMetadata?['provider'] == 'apple') return true;
  return identityProviders.contains('apple');
}

/// Hesap silmeden önce Apple kullanıcısından taze yetki kodu alır (Apple
/// belirtecinin iptali için). Apple kullanıcısı değilse `null`. Kullanıcı
/// pencereyi kapatırsa [AppleAuthException] (canceled) iletilir ve silme
/// durur; başka her hata yutulur ve silme kodsuz sürer (iptal silmeyi
/// engellemez).
Future<String?> appleCodeForDeletion({
  required bool isAppleUser,
  required AppleIdentityClient client,
}) async {
  if (!isAppleUser) return null;
  try {
    final credential = await client.signIn();
    final code = credential.authorizationCode;
    return code == null || code.isEmpty ? null : code;
  } on AppleAuthException catch (e) {
    if (e.kind == AppleAuthErrorKind.canceled) rethrow;
    return null;
  } catch (_) {
    return null;
  }
}
