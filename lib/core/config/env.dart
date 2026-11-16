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
    defaultValue: 'gemini-2.5-flash',
  );

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
