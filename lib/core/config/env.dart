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

  /// İsteğe bağlı (geçiş için): doluysa Gemini doğrudan bu anahtarla çağrılır;
  /// boşsa AI çağrıları sunucudaki `ai-proxy` Edge Function'ından geçer (oturum
  /// belirteciyle, anahtar uygulamada olmaz).
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// `GEMINI_API_KEY` boşsa AI proxy modu.
  static bool get usesAiProxy => geminiApiKey.trim().isEmpty;

  /// AI proxy adresi: `<SUPABASE_URL>/functions/v1/ai-proxy`.
  static String get aiProxyUrl => aiProxyUrlFor(supabaseUrl);

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

  static const String _rawGoogleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// İsteğe bağlı: Supabase ile Google girişi için Web OAuth istemci kimliği
  /// (`serverClientId`). Kimlik belirtecinin hedef kitlesi budur; Supabase >
  /// Authentication > Providers > Google "Authorized Client IDs" listesinde
  /// olmalıdır. Verilmemiş ya da biçimi geçersizse boştur; o zaman giriş
  /// ekranında Google düğmesi gizlenir, e-posta girişi çalışır.
  static String get googleWebClientId =>
      normalizeGoogleClientId(_rawGoogleWebClientId);

  /// Eksik olan zorunlu anahtarların adları (boşsa yapılandırma tamdır).
  static List<String> get missingKeys => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}

/// [supabaseUrl] (normalize edilmiş köken) için `ai-proxy` fonksiyonunun adresi;
/// adres boşsa boş metin.
String aiProxyUrlFor(String supabaseUrl) =>
    supabaseUrl.isEmpty ? '' : '$supabaseUrl/functions/v1/ai-proxy';

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

/// Google OAuth iOS ya da Web istemci kimliğini kırpar ve doğrular. Biçim
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
