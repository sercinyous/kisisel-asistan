/// Derleme zamanı yapılandırması.
///
/// Değerler `--dart-define` (veya `--dart-define-from-file=dart_defines.json`)
/// ile verilir; kaynak koda hiçbir anahtar yazılmaz.
abstract final class Env {
  static const String _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase proje adresi; yalnızca köken (`https://xxxx.supabase.co`).
  /// Panelde adres bazen `/rest/v1/` gibi bir yolla gösteriliyor; o yol kalırsa
  /// istemci `/rest/v1/auth/v1/...` adresine gider ve sunucu "Invalid path
  /// specified in request URL" döner. Bu yüzden yol, sorgu ve boşluk atılır.
  static String get supabaseUrl => normalizeSupabaseUrl(_rawSupabaseUrl);

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.8-flash',
  );

  static const String _rawGoogleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// İsteğe bağlı: Google ile giriş (Google Health) için iOS OAuth istemci
  /// kimliği. Verilmemiş ya da biçimi geçersizse boştur; o zaman Ayarlar'da
  /// Google seçeneği kapalı kalır, uygulamanın geri kalanı çalışır.
  static String get googleIosClientId =>
      normalizeGoogleClientId(_rawGoogleIosClientId);

  /// Eksik olan zorunlu anahtarların adları (boşsa yapılandırma tamdır).
  static List<String> get missingKeys => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
        if (geminiApiKey.isEmpty) 'GEMINI_API_KEY',
      ];
}

/// [raw] içinden yalnızca `şema://alan[:port]` kısmını döndürür. Şemasız
/// yazılmışsa (`xxxx.supabase.co`) `https://` eklenir. Ayrıştırılamazsa
/// kırpılmış hali döner; boş girdi boş kalır.
String normalizeSupabaseUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return raw.trim();
  return uri.origin;
}

/// Google OAuth iOS istemci kimliğini kırpar ve doğrular. Biçim
/// `<proje numarası>-<harf/rakam>.apps.googleusercontent.com` değilse boş
/// metin döner (yanlış değerle giriş penceresi açılmaz, seçenek kapalı kalır).
String normalizeGoogleClientId(String raw) {
  final value = raw.trim();
  return RegExp(r'^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$')
          .hasMatch(value)
      ? value
      : '';
}

/// iOS'ta Google girişinin uygulamaya dönüş adresi (Info.plist
/// `CFBundleURLSchemes`): istemci kimliğinin ters çevrilmiş hali,
/// `com.googleusercontent.apps.<proje numarası>-<harf/rakam>`.
/// `tool/configure_ios.sh` aynı dönüşümü yapar.
String reversedGoogleClientId(String clientId) {
  const suffix = '.apps.googleusercontent.com';
  final id = normalizeGoogleClientId(clientId);
  if (id.isEmpty) return '';
  return 'com.googleusercontent.apps.${id.substring(0, id.length - suffix.length)}';
}
