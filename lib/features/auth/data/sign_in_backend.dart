import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';

/// Supabase Auth'a giriş çağrıları. Testler sahtesini verir.
abstract interface class SignInBackend {
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Yeni e-posta/şifre hesabı açar. Oturum hemen açıldıysa `true`; e-posta
  /// onayı gerekiyorsa (oturum yok) `false`.
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  });

  /// Google kimlik belirteciyle giriş; ilk girişte hesap açılır.
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  });

  /// Apple kimlik belirteci ve ham nonce ile giriş; ilk girişte hesap açılır.
  /// [fullName] verilirse ve profilde görünen ad boşsa oraya yazılır.
  Future<void> signInWithAppleIdToken({
    required String idToken,
    required String rawNonce,
    String? fullName,
  });

  /// Şifre sıfırlama kodunu e-postayla gönderir. Adres kayıtlı olmasa da
  /// hata vermez (hesap varlığı sızmaz).
  Future<void> sendPasswordReset({required String email});

  /// E-postadaki sıfırlama kodunu doğrular; başarılıysa oturum açılır.
  /// Kod tek kullanımlıktır.
  Future<void> verifyResetCode({required String email, required String code});

  /// Açık oturumun şifresini değiştirir (sıfırlama ve Hesap > Şifre).
  Future<void> setNewPassword(String newPassword);

  /// Açık bir oturum var mı (kod zaten doğrulanmış olabilir).
  bool get hasSession;

  /// Kayıt onay kodunu doğrular; başarılıysa oturum açılır.
  Future<void> verifySignupCode({required String email, required String code});

  /// Kayıt onay kodunu yeniden gönderir.
  Future<void> resendSignupCode({required String email});
}

class SupabaseSignInBackend implements SignInBackend {
  SupabaseSignInBackend(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(email: email, password: password);
    return response.session != null;
  }

  @override
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  @override
  Future<void> signInWithAppleIdToken({
    required String idToken,
    required String rawNonce,
    String? fullName,
  }) async {
    final response = await _auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final userId = response.user?.id;
    final name = fullName?.trim() ?? '';
    if (userId == null || name.isEmpty) return;
    try {
      // Apple adı yalnızca ilk yetkilendirmede verir: profil adı boşsa yazılır.
      await _client
          .from('user_settings')
          .update(
              {'display_name': name.length > 60 ? name.substring(0, 60) : name})
          .eq('user_id', userId)
          .or('display_name.is.null,display_name.eq.');
    } catch (_) {
      // Ad yazılamasa da giriş geçerlidir; kullanıcı Ayarlar'dan girebilir.
    }
  }

  @override
  Future<void> sendPasswordReset({required String email}) =>
      _auth.resetPasswordForEmail(email);

  @override
  Future<void> verifyResetCode({
    required String email,
    required String code,
  }) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
  }

  @override
  Future<void> setNewPassword(String newPassword) async {
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.signup);
  }

  @override
  Future<void> resendSignupCode({required String email}) async {
    await _auth.resend(type: OtpType.signup, email: email);
  }
}

final signInBackendProvider = Provider<SignInBackend>(
  (ref) => SupabaseSignInBackend(ref.watch(supabaseClientProvider)),
);
