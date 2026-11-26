import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/google_auth.dart';

/// Kayıt, sıfırlama ve şifre değiştirmede en kısa şifre.
const int minPasswordLength = 8;

/// Sunucu yeni hesabı kaydedemediğinde (GoTrue "Database error saving new
/// user") gösterilen genel metin.
const String signUpFailedMessage =
    'Hesap oluşturulamadı. Biraz sonra tekrar dene.';

/// E-posta onayı gerektiren kayıttan sonra gösterilen bilgi.
const String confirmationSentMessage =
    'Onay e-postası gönderildi, gelen kutunu (ve spam) kontrol et.';

const String connectionFailedMessage = 'Bağlantı kurulamadı. Tekrar dene.';

/// Girişte gösterilecek Türkçe hata metni; kullanıcı Google penceresini
/// kapattıysa `null` (hata gösterilmez).
String? signInErrorMessage(Object error) {
  if (error is GoogleAuthException) {
    return error.kind == GoogleAuthErrorKind.canceled ? null : error.message;
  }
  if (error is AuthRetryableFetchException) return connectionFailedMessage;
  if (error is AuthException) return _authMessage(error);
  return connectionFailedMessage;
}

String _authMessage(AuthException error) {
  final message = error.message.toLowerCase();
  final code = error.code;
  if (message.contains('saving new user')) return signUpFailedMessage;
  if (code == 'user_already_exists' ||
      code == 'email_exists' ||
      message.contains('already registered')) {
    return 'Bu e-postayla zaten bir hesap var. Giriş yap.';
  }
  if (code == 'weak_password' || message.contains('password should be')) {
    return 'Şifre çok zayıf. En az $minPasswordLength karakter kullan.';
  }
  if (code == 'signup_disabled' || message.contains('signups not allowed')) {
    return 'Yeni kayıtlar şu an kapalı. Biraz sonra tekrar dene.';
  }
  if (code == 'invalid_credentials' || message.contains('invalid login')) {
    return 'E-posta ya da şifre hatalı.';
  }
  if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
    return 'E-posta adresin henüz doğrulanmamış.';
  }
  if (code == 'over_request_rate_limit' || error.statusCode == '429') {
    return 'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.';
  }
  if (code == 'provider_disabled' ||
      message.contains('audience') ||
      message.contains('provider is not enabled') ||
      message.contains('unsupported provider')) {
    return 'Google ile giriş sunucuda yapılandırılmamış. '
        'E-posta ile giriş yapabilirsin.';
  }
  return 'Giriş yapılamadı. Bilgilerini kontrol edip tekrar dene.';
}
