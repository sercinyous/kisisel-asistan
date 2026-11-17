import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/google_auth.dart';

/// Kayıt kapısı (davet almamış e-posta) reddi.
const String noInviteMessage =
    'Bu e-posta için davet yok. Ritim kullanan bir arkadaşından seni '
    'e-posta adresinle arkadaş olarak eklemesini iste, sonra tekrar dene.';

const String connectionFailedMessage = 'Bağlantı kurulamadı. Tekrar deneyin.';

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

/// Kayıt kapısı `before insert` tetikleyicisiyse GoTrue tetikleyicinin metnini
/// göstermez, genel "Database error saving new user" döner; "Before User
/// Created" kancasıysa metin olduğu gibi gelir. İkisi de aynı anlama gelir.
bool isNoInviteRejection(AuthException error) {
  final message = error.message.toLowerCase();
  return message.contains('davet yok') || message.contains('saving new user');
}

String _authMessage(AuthException error) {
  if (isNoInviteRejection(error)) return noInviteMessage;
  final message = error.message.toLowerCase();
  final code = error.code;
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
  return 'Giriş başarısız: ${error.message}';
}
