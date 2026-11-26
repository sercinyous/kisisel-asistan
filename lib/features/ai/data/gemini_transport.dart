import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/error_reporter.dart';

/// Kullanıcıya gösterilebilir (Türkçe) mesaj taşıyan AI hatası.
class AiParseException implements Exception {
  const AiParseException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiParseException($statusCode): $message';
}

/// Geçerli oturumun erişim belirtecini verir; oturum yoksa `null`.
typedef AccessTokenReader = Future<String?> Function();

/// [attempt]. başarısız denemeden sonra beklenecek süre (1'den başlar).
typedef RetryDelay = Duration Function(int attempt);

Duration defaultRetryDelay(int attempt) =>
    Duration(milliseconds: 600 * attempt);

/// Supabase oturumunun erişim belirteci. Süresi dolmuşsa (uygulama uzun süre
/// arka plandaysa) önce yenilenir; yenilenemezse `null` döner.
Future<String?> supabaseAccessToken(SupabaseClient client) async {
  final auth = client.auth;
  var session = auth.currentSession;
  if (session == null) return null;
  if (session.isExpired) {
    try {
      session = (await auth.refreshSession()).session;
    } catch (_) {
      return null;
    }
  }
  return session?.accessToken;
}

/// Gemini `generateContent` çağrısının taşıma katmanı: iki mod, ortak yeniden
/// deneme ve hata eşleme. Komut metni ve yanıt ayrıştırma burada değildir.
///
/// - Doğrudan mod ([apiKey] dolu, geçiş için): Google'a anahtarla gider.
/// - Proxy modu ([apiKey] boş): `<SUPABASE_URL>/functions/v1/ai-proxy` adresine
///   oturum belirteciyle gider; Gemini anahtarı yalnızca sunucudadır, modeli ve
///   günlük kotayı sunucu belirler.
///
/// Gövde iki modda da aynıdır (Gemini `generateContent` gövdesi); başarıda
/// yanıt gövdesi ham metin olarak döner.
class GeminiTransport {
  GeminiTransport({
    required String apiKey,
    required String model,
    String proxyUrl = '',
    String anonKey = '',
    AccessTokenReader? accessToken,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
    RetryDelay retryDelay = defaultRetryDelay,
    int maxAttempts = 3,
  })  : _apiKey = apiKey.trim(),
        _model = model,
        _proxyUrl = proxyUrl,
        _anonKey = anonKey,
        _accessToken = accessToken,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout,
        _retryDelay = retryDelay,
        _maxAttempts = maxAttempts;

  final String _apiKey;
  final String _model;
  final String _proxyUrl;
  final String _anonKey;
  final AccessTokenReader? _accessToken;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final RetryDelay _retryDelay;
  final int _maxAttempts;

  /// `GEMINI_API_KEY` boşsa istekler `ai-proxy` üzerinden gider.
  bool get usesProxy => _apiKey.isEmpty;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// [requestBody]'yi Gemini'ye (ya da proxy'ye) gönderir; 200 yanıtının ham
  /// gövdesini döndürür. Her hata Türkçe mesajlı [AiParseException] olarak çıkar.
  Future<String> post(Map<String, dynamic> requestBody) async {
    final body = jsonEncode(requestBody);

    AiParseException? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final (uri, headers) = await _target();
        final response = await _client
            .post(uri, headers: headers, body: body)
            .timeout(_timeout);

        if (response.statusCode == 200) {
          return utf8.decode(response.bodyBytes);
        }

        lastError = _errorFor(response);
        if (!_isRetryable(response.statusCode)) throw lastError;
      } on TimeoutException {
        lastError = const AiParseException(
          'Şu an yanıt alınamadı. Biraz sonra tekrar dene.',
        );
      } on SocketException {
        lastError = const AiParseException(
          'İnternete bağlanılamadı. Bağlantını kontrol edip tekrar dene.',
        );
      } on http.ClientException {
        lastError = const AiParseException(
          'AI servisine ulaşılamadı. Bağlantını kontrol edip tekrar dene.',
        );
      }

      if (attempt < _maxAttempts) {
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }
    throw lastError ??
        const AiParseException('AI servisi şu anda kullanılamıyor.');
  }

  // ------------------------------------------------------------- hedef

  Future<(Uri, Map<String, String>)> _target() async {
    const contentType = 'application/json; charset=utf-8';
    if (!usesProxy) {
      return (
        Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/$_model:generateContent',
        ),
        {'Content-Type': contentType, 'x-goog-api-key': _apiKey},
      );
    }

    final uri = Uri.tryParse(_proxyUrl);
    if (_proxyUrl.isEmpty || uri == null || !uri.hasAuthority) {
      throw _unavailable('ai-proxy: SUPABASE_URL tanımlı değil');
    }
    final token = await _accessToken?.call();
    if (token == null || token.isEmpty) {
      throw const AiParseException(_sessionMessage, statusCode: 401);
    }
    return (
      uri,
      {
        'Content-Type': contentType,
        'Authorization': 'Bearer $token',
        if (_anonKey.isNotEmpty) 'apikey': _anonKey,
      },
    );
  }

  // ----------------------------------------------------- yeniden deneme

  /// Doğrudan modda Gemini'nin 429'u (hız sınırı) geçicidir. Proxy modunda 429
  /// günlük kotadır, beklemek çözmez; proxy Gemini'nin geçici hatalarını
  /// 503/504 olarak iletir.
  bool _isRetryable(int status) => usesProxy
      ? status == 500 || status == 503 || status == 504
      : status == 429 || status == 500 || status == 503;

  // ------------------------------------------------------- hata eşleme

  /// Sunucu AI onayı bulamadı (403); onay sayfası yeniden açılır.
  static const String aiConsentRequiredMessage =
      'AI kullanımına onay vermedin. Onay verip tekrar dene ya da elle ekle.';

  static const String _sessionMessage =
      'Oturum bulunamadı ya da süresi doldu. Çıkış yapıp yeniden giriş yapın.';

  /// Kullanıcının düzeltemeyeceği sunucu/kurulum hataları için tek düz
  /// ileti; teknik ayrıntı hata kaydına gider.
  static const String unavailableMessage =
      'AI şu an kullanılamıyor. Biraz sonra tekrar dene; kayıtları elle de '
      'ekleyebilirsin.';

  static AiParseException _unavailable(String detail, {int? statusCode}) {
    ErrorReporter.current?.report(
      StateError('AI kullanılamıyor: $detail'),
      StackTrace.current,
    );
    return AiParseException(unavailableMessage, statusCode: statusCode);
  }

  AiParseException _errorFor(http.Response response) {
    final code = response.statusCode;
    if (usesProxy && (code == 402 || code == 404 || code == 502)) {
      return _unavailable(
        'ai-proxy $code ${_serverMessage(response) ?? ''}'.trim(),
        statusCode: code,
      );
    }
    final message = usesProxy
        ? _proxyMessage(code, _serverMessage(response))
        : _directMessage(code);
    return AiParseException(message, statusCode: code);
  }

  String _directMessage(int code) => switch (code) {
        400 =>
          'Bu metin işlenemedi. Biraz değiştirip tekrar dene ya da elle ekle.',
        401 || 403 => 'Gemini API anahtarı geçersiz ya da yetkisiz.',
        404 => 'Gemini modeli bulunamadı: $_model',
        402 => 'Gemini bakiyesi ya da faturalandırma tükendi (402). '
            'AI Studio > Billing bölümünden kredi ekleyin.',
        429 => 'AI şu an çok yoğun. Biraz sonra tekrar dene ya da elle ekle.',
        _ => 'Şu an yanıt alınamadı. Biraz sonra tekrar dene.',
      };

  String _proxyMessage(int code, String? serverMessage) => switch (code) {
        400 => 'Bu metin işlenemedi. Biraz değiştirip tekrar dene '
            'ya da elle ekle.',
        401 => _sessionMessage,
        403 => aiConsentRequiredMessage,
        413 => 'Metin çok uzun. Kısaltıp tekrar dene.',
        429 => serverMessage ??
            'Bugünkü AI hakkın doldu. Yarın tekrar dene ya da elle ekle.',
        _ => 'Şu an yanıt alınamadı. Biraz sonra tekrar dene.',
      };

  /// Proxy hata gövdesindeki `{"error": "<Türkçe ileti>"}`; yoksa `null`.
  static String? _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is Map && decoded['error'] is String) {
        final text = (decoded['error'] as String).trim();
        return text.isEmpty ? null : text;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
