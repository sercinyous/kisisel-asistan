/// Derleme zamanı yapılandırması.
///
/// Değerler `--dart-define` (veya `--dart-define-from-file=dart_defines.json`)
/// ile verilir; kaynak koda hiçbir anahtar yazılmaz.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
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
